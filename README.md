# F&F Two Wheeler Garage

Doorstep bike and scooter servicing. One Flutter app (customer, driver and admin screens), a FastAPI backend, and Supabase (PostgreSQL + Auth).

**Status: Phase 8 of 10 - customer app polish and support.** Admins manage services, packages, extra charges, serviceable PIN codes and time slots from the app; customers browse services, pick a package, address and time slot, review the price and place a booking, then view, change and cancel it. Admins can search and manage bookings through backend-only APIs. Customers pay for a booking online with Razorpay (test mode first); the backend verifies every payment and only then confirms the booking. Payment records can be read by admins through backend-only APIs. Admins create and manage drivers and assign them to paid bookings from the app; drivers sign in separately, see only their own bookings and move them through on the way, in progress and completed; customers see their driver, a progress timeline and in-app notifications, and the app keeps itself up to date while a booking is open. Phase 8 gives the customer, driver and shared screens one consistent look, loading skeletons, empty and error states, and a Help & support screen with the garage's configurable contact details. No web admin panel exists, and there is no push or SMS; WhatsApp is only a link that opens the WhatsApp app.

## Architecture

```
Flutter app  --HTTPS-->  FastAPI  --service-role key-->  Supabase (Postgres + Auth)
(public anon key only)   (business logic, RBAC,          (RLS as a second line of
                          payment secrets)                defence)
```

- Flutter never holds the Supabase service-role key or any payment secret. It holds only the public anon key, used for Supabase Auth sign-in.
- All business data goes through FastAPI, which uses the service-role key and enforces roles itself.
- Row Level Security is defence in depth: the `authenticated` role is read-only on business data, so a user calling Supabase's REST API directly with their own token cannot create bookings, set prices, forge payments or change roles.

## Folder structure

```
ff-garage/
  README.md
  .gitignore
  backend/                         FastAPI
    .env.example
    requirements.txt, requirements-dev.txt, pyproject.toml
    app/
      main.py                      app factory: CORS, docs, /api/v1 mount
      core/        config.py, logging.py, security.py (JWT verification), errors.py
      api/         deps.py, auth.py (current user + role guards), v1/endpoints/{health,profiles,admin_drivers,catalog,admin_catalog,admin_service_areas,admin_availability,bookings}.py
      schemas/     health, profile, driver, catalog, service_area, availability, booking, common (API contracts)
      services/    health, profile, driver_admin, catalog, service_area, availability, booking (business logic)
      db/          supabase.py, postgrest.py (error mapping), *_repository.py, auth_admin.py
      domain/      enums.py, availability.py (pure slot-availability rules), booking.py (status transitions, cancel/edit rules)
    tests/
  mobile/                          Flutter (customer app + driver panel)
    pubspec.yaml, analysis_options.yaml
    .env.example                   template for the git-ignored .env (public values only)
    lib/
      main.dart
      app/         app.dart, router/, theme/
      core/        config/, constants/, network/ (ApiClient, ApiException, AuthFailure), providers/, utils/validators.dart
      data/        models/, services/ (API calls, AuthGateway), repositories/, providers/
      features/    auth/ (splash, customer/driver/admin login, controller), home/, profile/, catalog/ (customer browse + PIN check), booking/ (address, schedule, summary, history, details, edit), admin/ (services, areas, availability)
    test/
  supabase/
    migrations/                    11 versioned SQL migrations (06 = auth hardening, 07 = categories + availability, 08 = booking workflow, 09 = payment workflow, 10 = driver assignment workflow, 11 = tracking + notifications)
    tests/                         shim + RLS/auth/catalog/booking/payment/assignment/tracking tests (01-07) + runner (test-only)
```

## Database

| Table | Purpose |
|---|---|
| `profiles` | One row per auth user: `role` (customer/driver/admin), name, phone, `driver_login_id`, `is_active` |
| `services` | What is offered, per vehicle type (bike/scooter) |
| `service_packages` | Priced packages inside a service, with inclusions |
| `extra_charges` | Spare-part / engine-oil / other charges, per service or per package |
| `service_areas` | Serviceable PIN codes (one row per PIN) |
| `bookings` | Customer bookings with name/address/price/service/package snapshots, schedule and status (see *Booking system*) |
| `booking_extra_charges` | Extra charges as they were when the booking was made (immutable snapshot rows) |
| `driver_assignments` | Which driver is assigned to a booking (history kept; one active per booking) |
| `time_slots` | Weekly visit windows: start/end, capacity (1-50), ISO weekdays, active flag. Overlapping active slots are refused by a trigger |
| `availability_exceptions` | Per-date overrides: close a whole day, close one slot, or open a slot on a day it does not normally run (optional capacity, customer-visible reason) |
| `payments` | Payment attempts: booking, amount, currency, gateway order/payment IDs, receipt, method, status, `needs_review` flag (see *Payments*) |
| `payment_events` | Log of every verification and webhook the backend processed (idempotency key and outcome); admin-readable |

`services` also has a `category`. Deleting a service area never touches bookings (they keep their own address snapshot). Function `slot_booking_counts` (service-role only) counts non-cancelled bookings per date and slot.

Enums: `user_role`, `vehicle_type`, `extra_charge_type`, `booking_status`, `payment_status`. They are mirrored in `backend/app/domain/enums.py` and `mobile/lib/data/models/enums.dart`; a backend test fails if the three drift apart.

### Applying the migrations

Migrations are in `supabase/migrations/` and must run in filename order.

- **psql** (any Postgres that has Supabase's `auth` schema, i.e. your Supabase project):
  ```bash
  for f in supabase/migrations/*.sql; do psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -1 -f "$f"; done
  ```
  Use the direct or pooler connection string from Supabase > Project Settings > Database.
- **Supabase CLI:** `supabase link --project-ref <ref>` then `supabase db push`. (If `supabase/config.toml` is missing, run `supabase init` first; it keeps the existing `migrations/` folder.)
- **SQL editor:** paste each file in order.

### Creating the first admin

Sign-up always creates a `customer`; roles cannot be self-assigned. To bootstrap an admin:

1. Create the user in Supabase Dashboard > Authentication > Users.
2. In the SQL editor (runs as `postgres`):
   ```sql
   update public.profiles set role = 'admin' where id = '<that user''s uuid>';
   ```

Drivers are created by an admin through the backend (see *Creating a driver* below); the database trigger sets `role = 'driver'` and `driver_login_id` in the same step as the auth user is created.

### Testing the migrations locally

Needs a **local** PostgreSQL (the script refuses non-local hosts because its shim creates an `auth` schema):

```bash
PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres supabase/tests/run_migration_tests.sh
```

It creates a scratch database, loads a Supabase shim, applies every migration, runs the RLS/constraint/booking/payment/assignment/tracking tests (01-07), then drops the database.

## Authentication and roles (Phase 2)

```
Flutter --sign in (anon key)--> Supabase Auth --JWT--> Flutter
Flutter --Authorization: Bearer <JWT>--> FastAPI
FastAPI: verify JWT locally -> load profile + role from `profiles` -> allow / deny
```

- **Customers** register and sign in with email + password (Supabase Auth). A database trigger creates their `profiles` row with role `customer`; a role can never be chosen by the client.
- **Drivers** sign in on a separate screen with a driver ID + password given to them. There is no driver sign-up. An admin creates them through the backend; the app turns the ID into the login email `<driver_id>@drivers.ffgarage.invalid`. Database triggers stop anyone from signing up on, or changing an email to, that domain.
- **Admin** is a role for backend operations only (protected API calls). The Flutter app has no admin screens and turns admin accounts away at login.
- **Token checks (FastAPI):** signature (asymmetric keys via the project's JWKS, or legacy HS256 with `SUPABASE_JWT_SECRET`), expiry, issuer, audience, `role=authenticated`, anonymous tokens rejected, algorithm allow-list.
- **Roles come from the database, not the token**, on every request, so promoting, demoting or disabling a user takes effect immediately.
- Status codes: `401` missing/invalid/expired token, `403` no profile / disabled / wrong role, `503` auth not configured or Supabase unreachable.

| Endpoint | Who |
|---|---|
| `GET /api/v1/profiles/me` | any active user |
| `PATCH /api/v1/profiles/me` (name, phone) | customer |
| `GET/POST /api/v1/admin/drivers` | admin |
| `GET/PATCH /api/v1/admin/drivers/{id}` (name, phone, `is_active`) | admin |
| `POST /api/v1/admin/drivers/{id}/password` | admin |

Disabling a driver sets `is_active=false` and bans the Auth user. Existing access tokens stay valid until they expire (about an hour), but the backend rejects them immediately because the profile check fails.

### Creating a driver

Use an admin's access token (sign in as the admin with Supabase Auth, e.g. from the Swagger UI "Authorize" button):

```bash
curl -X POST "$API/api/v1/admin/drivers" -H "Authorization: Bearer $ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d '{"driver_id":"ravi01","password":"a-strong-password","full_name":"Ravi Kumar","phone":"9876543210"}'
```

### Supabase project settings to check

- **Authentication > Providers > Email:** decide whether "Confirm email" is on. If it is, customers see a "check your email" screen after registering; if not, they are signed in immediately. Driver accounts are created pre-confirmed, so this setting does not affect them.
- **Verify the `.invalid` driver domain is accepted** by your project (create one driver and sign in). If Supabase rejects it, pick another domain and change all three together: `public.driver_email_domain()` in migration 6, `DRIVER_EMAIL_DOMAIN` (backend env) and `defaultDriverEmailDomain` in `mobile/lib/core/config/app_config.dart`. A backend test fails if they differ.
- **JWT signing keys:** new projects use asymmetric keys and need nothing extra. A project still on the legacy shared secret needs `SUPABASE_JWT_SECRET` set in the backend.

## Service catalog, areas and availability (Phase 3)

**Who can do what.** Every endpoint needs a signed-in, active user. Reads under `/catalog` and `/availability` are open to any role; everything under `/admin/...` is admin-only and enforced in the backend on every request (401 bad token, 403 wrong role). RLS repeats the rule in the database: customers and drivers cannot write catalog, area or availability tables.

Customer endpoints (`/api/v1`):

| Method | Path | Notes |
|---|---|---|
| GET | `/catalog/services?vehicle_type=` | Active services that have at least one active package |
| GET | `/catalog/services/{id}` | One service with active packages and charges |
| GET | `/service-areas/check?pincode=` | `serviceable` yes/no; unknown and inactive PINs look identical |
| GET | `/availability?start_date=&end_date=` | Per-day, per-slot availability, max 31 days |

Admin endpoints:

| Path | Methods |
|---|---|
| `/admin/services`, `/admin/services/{id}` | GET, POST / GET, PATCH (vehicle type is immutable) |
| `/admin/services/{id}/packages`, `/admin/packages/{id}` | POST / PATCH |
| `/admin/services/{id}/extra-charges`, `/admin/extra-charges/{id}` | POST / PATCH, DELETE |
| `/admin/service-areas`, `/admin/service-areas/{id}` | GET, POST / PATCH, DELETE |
| `/admin/availability/slots`, `.../slots/{id}` | GET, POST / PATCH, DELETE |
| `/admin/availability/exceptions`, `.../exceptions/{id}` | GET (start_date and end_date required), POST / PATCH, DELETE |

Money is sent and returned as decimal strings (`"499.00"`, max 2 decimals). Validation errors are 422, duplicates and overlaps 409, unknown ids 404.

**Availability rules**, first match wins: past date, beyond the booking window, whole-day closure, slot not running that weekday (unless opened by an exception), slot closed by an exception, lead time passed, fully booked. Dates and times use `BUSINESS_TIMEZONE`. A slot with upcoming bookings cannot have its times changed or be deleted; deactivate it instead. `AvailabilityService.ensure_bookable(day, slot_id)` is the check the booking flow (Phase 4) calls.

**Admin in the app.** The customer login has an "Admin sign in" link (`/admin-login`) that opens the admin screens; non-admin accounts are refused there, and the backend checks the role regardless. Create the first admin with the SQL under *Creating the first admin*.

## Booking system (Phase 4)

**Flow.** Customer opens a service, taps *Book this package*, enters PIN code and address (PIN checked with the server), picks a date and time slot, reviews the server-calculated price with optional add-ons, and confirms. The booking is created as `pending_payment` and the customer lands on its detail page. Nothing is sent to the server until Confirm.

**Statuses and transitions** (enforced in the database trigger, mirrored in `backend/app/domain/booking.py`; a test fails if they drift):

| From | Can become |
|---|---|
| `pending_payment` | `confirmed`, `cancelled` |
| `confirmed` | `assigned`, `cancelled` |
| `assigned` | `confirmed`, `on_the_way`, `cancelled` |
| `on_the_way` | `in_progress`, `cancelled` |
| `in_progress` | `completed`, `cancelled` |
| `completed`, `cancelled` | final (rows become read-only) |

Through the API only `pending_payment`, `confirmed` and `cancelled` are reachable. A booking becomes `confirmed` only when the backend verifies a payment (see *Payments*); an admin can cancel by hand but can no longer confirm by hand (changed in Phase 5). `assigned`, `on_the_way`, `in_progress` and `completed` are reached only through driver assignment and the driver's own steps (see *Drivers and assignment*).

**Cancellation and changes.** A customer can cancel a `pending_payment` booking any time, and a `confirmed` or `assigned` one until `BOOKING_CANCEL_CUTOFF_HOURS` (default 4) before the slot starts; never after `on_the_way`. Cancelling twice is harmless. A customer can change address, landmark, notes, PIN code, or date and slot together, only while `pending_payment` or `confirmed` and before the cutoff. Service, package, price, extras and status can never be changed by the customer. Someone else's booking looks exactly like a missing one (404). The responses carry `can_cancel`, `can_modify` and a reason, so the app never guesses.

**Prices.** The server reads prices from the catalogue and stores a snapshot (package price, chosen extras, total, service/package names, inclusions, address, customer name and phone). The app sends only ids and the total it showed (`expected_total`); a mismatch is refused with 409 so the customer reviews the new price. Only active, applicable, fixed-amount extras can be ticked. At-actuals charges are listed as "may apply" and are not in the total.

**Duplicates and conflicts** (database-level, so races are safe): `client_request_id` makes a retried Confirm return the same booking (200 instead of 201); one active booking per customer per date and slot; slot capacity is enforced under an advisory lock (409 "slot is full").

Customer endpoints (`/api/v1`, customer role only):

| Method | Path | Notes |
|---|---|---|
| POST | `/bookings/quote` | Price summary for a package and optional extras |
| POST | `/bookings` | Create (201; 200 when replaying the same `client_request_id`) |
| GET | `/bookings?status=&limit=&offset=` | Own bookings, newest first, with total |
| GET / PATCH | `/bookings/{id}` | Own booking / permitted changes |
| POST | `/bookings/{id}/cancel` | Optional reason |

Admin endpoints (admin role only, backend API only; there is no admin booking screen yet):

| Method | Path | Notes |
|---|---|---|
| GET | `/admin/bookings` | Filters: `status` (repeatable), `vehicle_type`, `date_from`, `date_to`, `pincode`, `customer_id`, `q` (booking number like `FF-000012`, phone, or name), `limit`, `offset` |
| GET | `/admin/bookings/{id}` | Full detail with `allowed_status_updates` |
| PATCH | `/admin/bookings/{id}/status` | Only `cancelled`; any other target is 422 (confirmation comes from a verified payment) |

## Payments (Phase 5)

**Flow.** On a `pending_payment` booking the customer taps *Pay*. The app asks the backend to start a payment; the backend creates a Razorpay order for the booking's own total (the app never sends an amount) and returns the public key id and order id. The app opens Razorpay's checkout and gets back `order_id`, `payment_id` and `signature`. It sends those to the backend, which checks the signature, asks Razorpay for the payment, checks amount and currency, and only then marks the payment successful and the booking `confirmed`. The Razorpay webhook does the same independently, so a payment is still recorded if the app is closed mid-payment. **A success reported by the app alone never confirms anything.**

**One place decides.** Both paths call the SQL function `apply_payment_event` (service role only). In one transaction, with row locks, it checks the order, amount and currency, updates the payment and the booking, and records the event. It is idempotent: a replayed callback or webhook changes nothing and answers `already_processed`/`duplicate_event`.

| Situation | Result |
|---|---|
| Valid payment, right amount | payment `successful`, booking `confirmed` |
| Same callback or webhook again | no change (idempotent) |
| Wrong signature | 400, nothing stored |
| Amount or currency differs from the booking | payment `failed` and flagged `needs_review`, booking stays `pending_payment` |
| Declined / failed | payment `failed`; the customer can retry (a failed payment may still become successful if Razorpay later reports success) |
| Customer closes checkout | payment `cancelled` |
| Bank not settled yet | payment stays `pending`; booking not paid |
| Second successful payment for a paid booking | recorded and flagged `needs_review` (duplicate) |
| Payment arrives for a booking that was cancelled | recorded and flagged `needs_review` |
| Booking cancelled | open attempt is cancelled; a paid booking is flagged `needs_review` |

Only one open attempt exists per booking (a retry reuses it while recent, otherwise it is replaced). `needs_review` marks money a person must deal with. **Refunds are not automated** in this phase: an admin reads the flagged payments and refunds in the Razorpay dashboard. Customers never see `needs_review`.

Customer endpoints (`/api/v1`, customer role; someone else's booking or payment is a 404):

| Method | Path | Notes |
|---|---|---|
| POST | `/bookings/{id}/payments` | Start or resume payment; returns the payment and checkout options. 409 if already paid, 422 if the booking is not payable (e.g. cancelled), 503 if payments are off |
| GET | `/bookings/{id}/payments` | Attempts for the booking |
| GET | `/payments/{id}` | One payment |
| POST | `/payments/{id}/verify` | Body `razorpay_order_id`, `razorpay_payment_id`, `razorpay_signature` |
| POST | `/payments/{id}/cancel` | Customer closed the checkout |

Webhook: `POST /api/v1/webhooks/razorpay` (public, authenticated by the `X-Razorpay-Signature` HMAC over the raw body). Handles `payment.captured`, `order.paid` and `payment.failed`; other events are acknowledged and ignored.

Admin (admin role, read-only, backend API only):

| Method | Path | Notes |
|---|---|---|
| GET | `/admin/payments` | Filters: `status` (repeatable), `booking_id`, `customer_id`, `needs_review`, `date_from`, `date_to`, `q`, `limit`, `offset` |
| GET | `/admin/payments/{id}` | Payment with its event log |

Any write method on these routes is 405.

Bookings in the customer app carry `payment` (status, amount, method, transaction ID, paid time, failure reason), `is_paid` and `can_pay`. The booking detail screen shows the payment section and a *Pay* button; the history list shows a payment line.

### Razorpay setup

1. Create a Razorpay account and, in the Dashboard, switch to **Test mode**. *Settings > API Keys > Generate Test Key* gives `rzp_test_...` (key id) and the key secret.
2. Make sure payment capture is **automatic** (*Settings > Payment Capture*). A payment that is only authorized stays `pending` here.
3. Put in `backend/.env`: `PAYMENT_GATEWAY_PROVIDER=razorpay`, `PAYMENT_GATEWAY_KEY_ID`, `PAYMENT_GATEWAY_KEY_SECRET`.
4. Webhook: *Settings > Webhooks > Add*. URL `https://<your-backend-host>/api/v1/webhooks/razorpay` (public HTTPS; use a tunnel such as ngrok for local tests). Active events: `payment.captured`, `payment.failed`, `order.paid`. Choose a secret and set the same value as `PAYMENT_GATEWAY_WEBHOOK_SECRET`.
5. Apply migration 9, restart the backend, and pay with Razorpay's test cards/UPI. Test payments are marked as such in the app.

Flutter: `razorpay_flutter` is a dependency of the app. After `flutter pub get` and `flutter create`, set the Android `minSdkVersion` to at least 19 (21 recommended) and use a recent iOS deployment target (see the plugin's README). No gateway secret or key is configured in Flutter; the key id arrives from the backend with each checkout.

### Going live

- Complete Razorpay KYC and generate **live** keys (`rzp_live_...`); replace the key id and secret and create the webhook again in live mode with its own secret.
- Run the backend on HTTPS with `APP_ENV=production`; the backend refuses to start with payments on and no webhook secret.
- Keep all three gateway values in the host's secret store, not in the repository or the app.
- Decide who reviews `needs_review` payments and handles refunds (manual in this phase).

## Drivers and assignment (Phase 6)

**Driver accounts** are managed by admins in the app (Admin > Drivers: add, edit name/mobile, switch on/off, reset password) through the Phase 2 endpoints. The list shows each driver's `open_bookings`; switching a driver off warns when they still have open bookings. A switched-off driver is locked out at once, keeps their assignments, and the admin must reassign them.

**Assignment** (Admin > Bookings, "Needs driver" filter). All changes go through SQL functions (service role only) that lock the booking and run in one transaction, so two admins or a driver and an admin cannot disagree.

| Rule | Behaviour |
|---|---|
| Who can be assigned | Only a booking with a verified payment, in `confirmed`, `assigned` or `on_the_way` |
| Driver | Must exist, have the driver role and be active |
| Same driver again | No change (safe retry) |
| Reassign | Keeps the booking status; the old assignment is closed and kept as history; refused once `in_progress` |
| Remove driver | Only while `assigned`; the booking returns to `confirmed` |
| Double booking | A driver cannot hold two open visits with overlapping times on one date (409) |
| Cancel | Still the admin/customer cancel rules of Phase 4/5; a paid booking cancelled gets its payment flagged `needs_review` as before |

**Driver steps.** `assigned` > `on_the_way` > `in_progress` > `completed`, one step at a time. Repeating the current step is accepted and changes nothing. A driver cannot cancel, skip, go back, or touch a booking that is not currently assigned to them (404, identical to a missing booking). Completing sets `completed_at`. Drivers never receive prices or payment details.

| Endpoint | Who |
|---|---|
| `PUT /api/v1/admin/bookings/{id}/driver` `{driver_id}` | admin: assign or reassign |
| `DELETE /api/v1/admin/bookings/{id}/driver` | admin: remove driver |
| `GET /api/v1/admin/bookings/{id}/assignments` | admin: assignment history |
| `GET /api/v1/admin/drivers/{id}/bookings?scope=open\|history` | admin: one driver's bookings |
| `GET /api/v1/driver/bookings?scope=open\|history&limit=&offset=` | driver: own bookings |
| `GET /api/v1/driver/bookings/{id}` | driver: one own booking |
| `POST /api/v1/driver/bookings/{id}/status` `{status}` | driver: next step |

Admin booking responses carry `assignment`, `can_assign` and `can_unassign`; customer booking responses carry `driver` (`name`, `phone` only, hidden once cancelled). Customers see updates when they open or refresh a screen (no push or live subscription yet).

## Tracking and notifications (Phase 7)

**What the customer sees.** The booking screen shows the number, service, address, date and time, status, payment status, the driver once assigned, and a **progress timeline**: placed > confirmed > driver assigned > on the way > in progress > completed. A cancelled booking shows only the steps it reached and then "Booking cancelled"; a driver who is removed puts the booking back to "waiting for a driver". The history list shows a plain status line per booking ("Waiting for payment", "Ravi is on the way", "Completed 21 Oct"), payment, driver and dates.

**Where the data comes from.** Migration 11 adds two tables that are written **only by database triggers** on `bookings`, `driver_assignments` and `payments`, so every path that changes a booking (customer, admin API, driver API, payment confirmation) is recorded the same way, and nothing is announced that did not happen:

| Table | Holds |
|---|---|
| `booking_status_events` | one row each time a booking enters a status (the timeline; `timeline` on the booking responses) |
| `notifications` | the customer's updates: `booking_confirmed`, `payment_failed`, `driver_assigned`, `driver_changed`, `driver_removed`, `driver_on_the_way`, `service_started`, `service_completed`, `booking_cancelled` |

A successful payment produces one "Booking confirmed" notification, created only when the backend has verified the payment and confirmed the booking (Phase 5); a failed payment produces "Payment failed" only while the booking is still unpaid. Repeating an action (same driver again, same step again, a replayed webhook) creates nothing new. Customers can read only their own rows; drivers and admins have no notifications. Nothing in the app can mark a booking or payment successful.

| Endpoint | Who |
|---|---|
| `GET /api/v1/notifications?unread_only=&limit=&offset=` | customer: own notifications, newest first (`unread` = overall unread count) |
| `GET /api/v1/notifications/unread-count` | customer |
| `POST /api/v1/notifications/read` `{ids?}` | customer: mark those (or all) read; other people's ids are ignored |

**Getting updates to the app.** There is no push connection in this phase. The app asks: the bell on the customer home polls the unread count (every 30 s while visible); when it goes up, booking screens reload; an open booking checks for changes every 30 s until it is completed or cancelled. Pull-to-refresh works everywhere. **Push (FCM) is not included:** it would need a Firebase project and device-token storage, and the `notifications` rows are what a backend sender would read; credentials would stay on the backend.

## UI polish and support (Phase 8)

**Look and feel.** One Material 3 theme (`app/theme/app_theme.dart`) drives every screen: 12 dp rounded controls, 48 dp minimum touch targets on filled, outlined, text and icon buttons, filled inputs with a clear focus border, floating snack bars. Light and dark follow the phone. `app/responsive_shell.dart` wraps every screen: content is at most 720 dp wide (tablets, web), system font scaling is honoured up to 1.6x, and tapping outside a field closes the keyboard.

**Shared states.** `AsyncView` shows a spinner (or a static `ListSkeleton` on list screens), an error message with **Retry**, or the data; `EmptyView` has an icon and optional action; `showSuccessSnack` confirms saves, cancellations and driver steps. Forms validate as the user types after the first interaction, scroll above the keyboard and dismiss it on drag. Booking status is shown with an icon as well as colour.

**Screens touched.** Customer home (support entry), service list, booking history, booking detail ("Call driver", "Help with this booking"), payment (success state, "Contact support" when stuck), driver dashboard and job screen ("Call customer", "Open in maps"), profile (header, support link, **confirmation before sign out**). Nothing was added to the booking, payment, driver or notification logic; all data still comes from the FastAPI endpoints.

**Help & support.** `GET /api/v1/support/contact` (any signed-in role) returns the garage's contact details from environment variables, so changing a phone number needs no app release. Unset values come back empty and the app hides them.

| Variable | Notes |
|---|---|
| `GARAGE_NAME` | Default `F&F Two Wheeler Garage` |
| `GARAGE_PHONE` | Opens the dialler. Digits with optional leading `+` are kept, everything else removed |
| `GARAGE_WHATSAPP` | Number with country code, e.g. `919876543210`; opens `wa.me` with a pre-filled message that quotes the booking code when opened from a booking |
| `GARAGE_EMAIL`, `GARAGE_ADDRESS`, `GARAGE_HOURS` | Shown as given; the address opens in maps |

The screen also lists four short "common questions". If the device cannot open a call, mail or map link (a tablet, the web) the app shows the detail so it can be copied; every row has a copy button.

**Native setup for links (`url_launcher`).** After generating the native folders, add the query entries the plugin needs:

- Android, `android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:
  `<queries><intent><action android:name="android.intent.action.VIEW"/><data android:scheme="tel"/></intent><intent><action android:name="android.intent.action.VIEW"/><data android:scheme="mailto"/></intent><intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent></queries>`
- iOS, `ios/Runner/Info.plist`: `<key>LSApplicationQueriesSchemes</key><array><string>tel</string><string>mailto</string><string>https</string></array>`

**Platforms.** Android and iOS are the supported targets. Flutter Web is not a target of this project: `razorpay_flutter` has no web support, so payment cannot work there; the rest of the UI is written to be width-responsive.

## Environment variables

Backend: copy `backend/.env.example` to `backend/.env`.

| Variable | Required | Notes |
|---|---|---|
| `APP_ENV` | no | `development` (default), `test`, `staging`, `production` |
| `APP_NAME`, `DEBUG`, `LOG_LEVEL`, `API_V1_PREFIX` | no | Defaults in `.env.example` |
| `ENABLE_DOCS` | no | `true` serves `/docs` and `/redoc`; set `false` to hide |
| `CORS_ORIGINS` | no | Comma-separated browser origins. `*` is rejected in production |
| `SUPABASE_URL` | yes in production | Project URL |
| `SUPABASE_ANON_KEY` | yes in production | Public anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | yes in production | **Secret.** Backend only |
| `SUPABASE_JWT_SECRET` | only for legacy HS256 projects | **Secret.** Leave blank on projects using asymmetric signing keys |
| `SUPABASE_JWT_AUDIENCE` | no | Default `authenticated` |
| `DRIVER_EMAIL_DOMAIN` | no | Default `drivers.ffgarage.invalid`; must match the SQL function and the Flutter constant |
| `BUSINESS_TIMEZONE` | no | IANA zone used for dates and slot times. Default `Asia/Kolkata` |
| `BOOKING_WINDOW_DAYS` | no | How far ahead customers can book, 1-365. Default 30 |
| `BOOKING_LEAD_MINUTES` | no | Minimum notice before a slot starts, 0-1440. Default 120 |
| `BOOKING_CANCEL_CUTOFF_HOURS` | no | Customers cannot cancel or change a confirmed/assigned booking within this many hours of the slot, 0-168. Default 4 |
| `PAYMENT_GATEWAY_PROVIDER` | no | `razorpay` to turn payments on; blank = off (payment endpoints answer 503 and `can_pay` is false) |
| `PAYMENT_GATEWAY_KEY_ID` | with provider | `rzp_test_...` or `rzp_live_...`. Not secret (the checkout needs it) |
| `PAYMENT_GATEWAY_KEY_SECRET` | with provider | **Secret.** Backend only, never in Flutter or responses |
| `PAYMENT_GATEWAY_WEBHOOK_SECRET` | production | **Secret.** Must equal the secret on the Razorpay webhook. Required when `APP_ENV=production` with payments on |
| `PAYMENT_GATEWAY_BASE_URL` | no | Default `https://api.razorpay.com/v1` (must be https) |
| `PAYMENT_GATEWAY_TIMEOUT_SECONDS` | no | Gateway request timeout. Default in `.env.example` |
| `PAYMENT_CHECKOUT_NAME` | no | Business name shown in the checkout window |
| `GARAGE_NAME`, `GARAGE_PHONE`, `GARAGE_WHATSAPP`, `GARAGE_EMAIL`, `GARAGE_ADDRESS`, `GARAGE_HOURS` | no | Contact details for the Help & support screen (see Phase 8). Blank = hidden |
| `PAYMENT_ATTEMPT_REUSE_MINUTES` | no | An open attempt younger than this is reused instead of creating a new gateway order. Default 30 |

Flutter (public values only), via `mobile/.env` (copy from `mobile/.env.example`; git-ignored). It is loaded with `flutter_dotenv` before the app starts and **is bundled into the app, so anyone can read it**. Never put a Supabase service-role key, database password, JWT secret or payment-gateway secret in it: those stay in `backend/.env`.

| Variable | Notes |
|---|---|
| `API_BASE_URL` | Backend URL including `/api/v1`. Default `http://10.0.2.2:8000/api/v1` (Android emulator -> host). iOS simulator: `http://localhost:8000/api/v1` |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Required. Public anon key only |
| `DRIVER_EMAIL_DOMAIN` | Optional; default `drivers.ffgarage.invalid`. Must match the backend |

If `.env` is missing, still has the example placeholders, has a malformed URL, holds a service-role key in `SUPABASE_ANON_KEY`, or contains a variable whose name looks like a server secret (`SERVICE_ROLE`, `SECRET`, `PASSWORD`, `DATABASE_URL`, `JWT`...), the app does not crash: it shows an "App configuration needed" screen that names the problems (never the values) and how to fix them.

## Run commands

### Backend

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env            # then edit
uvicorn app.main:app --reload   # http://127.0.0.1:8000
```

- Liveness: `GET /api/v1/health`
- Readiness: `GET /api/v1/health/ready` (200 when Supabase is configured and reachable, else 503)
- Swagger UI: `/docs`, ReDoc: `/redoc`

```bash
pytest                          # tests
ruff check . && ruff format --check .
```

### Flutter

The native `android/` and `ios/` folders are not committed by Phase 1; generate them once (existing files are not overwritten by default):

```bash
cd mobile
flutter create --platforms=android,ios --org com.ffgarage --project-name ff_garage .
flutter pub get
cp .env.example .env     # then edit (required: .env is a bundled asset)
flutter run
```

Android debug builds talk to an `http://` backend only if cleartext traffic is allowed: add `android:usesCleartextTraffic="true"` to the `<application>` tag in `android/app/src/debug/AndroidManifest.xml` (debug only; production should use HTTPS).

```bash
flutter analyze
flutter test
```
