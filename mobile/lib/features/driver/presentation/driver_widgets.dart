import 'package:flutter/material.dart';

import '../../../data/models/driver_job.dart';
import '../../../data/models/enums.dart';

/// The button label for the step a driver takes next.
String driverStepLabel(BookingStatus next) {
  switch (next) {
    case BookingStatus.onTheWay:
      return "I'm on my way";
    case BookingStatus.inProgress:
      return 'Start service';
    case BookingStatus.completed:
      return 'Mark as completed';
    default:
      return 'Update status';
  }
}

/// What the driver is told once a step is done.
String driverStepDone(BookingStatus status) {
  switch (status) {
    case BookingStatus.onTheWay:
      return 'Marked as on the way';
    case BookingStatus.inProgress:
      return 'Service started';
    case BookingStatus.completed:
      return 'Booking completed';
    default:
      return 'Status updated';
  }
}

/// The question asked before a step is recorded.
String driverStepQuestion(BookingStatus next) {
  switch (next) {
    case BookingStatus.onTheWay:
      return 'Tell the customer you are on your way?';
    case BookingStatus.inProgress:
      return 'Start the service now?';
    case BookingStatus.completed:
      return 'Mark this service as completed? This cannot be undone.';
    default:
      return 'Update the status?';
  }
}

/// A short "Tap to see the visit" line for a job tile.
String jobAddressLine(DriverJob job) =>
    '${job.addressLine}, ${job.city} ${job.pincode}';
