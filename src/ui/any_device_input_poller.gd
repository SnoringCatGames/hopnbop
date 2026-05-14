class_name AnyDeviceInputPoller
extends PlatformAnyDeviceInputPoller
## Game-side alias for PlatformAnyDeviceInputPoller.
##
## The platform poller reads keyboard-partition bindings
## from PlatformInputDeviceManager. Hopnbop's
## InputDeviceManager owns the same KEYBOARD_PARTITION_BINDINGS
## const array, so the two pollers behave identically.
## Subclassing (rather than direct use of the platform
## class) keeps callers terse and lets a future hopnbop-
## specific override layer in here without touching every
## screen.
