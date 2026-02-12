# frozen_string_literal: true

module Teek
  module SDL2
    # An SDL2 GameController for polling buttons, analog sticks, and triggers.
    #
    # Gamepad wraps SDL2's GameController API, which automatically maps
    # physical controls to an Xbox-style layout. This is higher-level than
    # the raw Joystick API and works with most modern controllers out of
    # the box (Xbox, PlayStation, Switch Pro, etc.).
    #
    # @example Polling a connected gamepad
    #   gp = Teek::SDL2::Gamepad.first
    #   if gp
    #     puts gp.name
    #     puts "A pressed: #{gp.button?(:a)}"
    #     puts "Left stick X: #{gp.axis(:left_x)}"
    #     gp.close
    #   end
    #
    # @example Event-driven input
    #   Teek::SDL2::Gamepad.on_button do |instance_id, button, pressed|
    #     puts "#{button} #{pressed ? 'pressed' : 'released'}"
    #   end
    #
    #   # In your game loop:
    #   Teek::SDL2::Gamepad.poll_events
    #
    # @example Hot-plug detection
    #   Teek::SDL2::Gamepad.on_added do |device_index|
    #     gp = Teek::SDL2::Gamepad.open(device_index)
    #     puts "Connected: #{gp.name}"
    #   end
    class Gamepad

      # @!group Class methods (C-defined)

      # @!method self.init_subsystem
      #   Initialize the SDL2 gamepad subsystem. Called automatically by
      #   other methods, but can be called early for hot-plug detection.
      #   @return [nil]

      # @!method self.shutdown_subsystem
      #   Shut down the gamepad subsystem. Existing Gamepad objects become invalid.
      #   @return [nil]

      # @!method self.count
      #   Returns the number of connected gamepads recognized by SDL2.
      #   @return [Integer]

      # @!method self.open(index)
      #   Open the gamepad at the given device index.
      #   @param index [Integer] device index (0-based)
      #   @return [Gamepad]
      #   @raise [ArgumentError] if index is negative
      #   @raise [RuntimeError] if index is out of range or device cannot be opened

      # @!method self.first
      #   Open the first available gamepad.
      #   @return [Gamepad, nil] nil if no gamepads are connected

      # @!method self.all
      #   Open and return all connected gamepads.
      #   @return [Array<Gamepad>]

      # @!method self.poll_events
      #   Pump SDL events and dispatch gamepad events to registered callbacks.
      #   Call this periodically (e.g. every 16–50ms) for responsive input.
      #   @return [Integer] number of events processed

      # @!method self.buttons
      #   List of valid button symbols.
      #   @return [Array<Symbol>]

      # @!method self.axes
      #   List of valid axis symbols.
      #   @return [Array<Symbol>]

      # @!method self.attach_virtual
      #   Create a virtual gamepad device for testing without hardware.
      #   @return [Integer] device index (pass to {.open})
      #   @raise [RuntimeError] if a virtual device is already attached

      # @!method self.detach_virtual
      #   Remove the virtual gamepad created by {.attach_virtual}.
      #   @return [nil]

      # @!method self.virtual_device_index
      #   Device index of the virtual gamepad.
      #   @return [Integer, nil] nil if no virtual device is attached

      # @!method self.on_button {|instance_id, button, pressed| ... }
      #   Register a callback for button press/release events.
      #   @yieldparam instance_id [Integer] SDL joystick instance ID
      #   @yieldparam button [Symbol] button name (e.g. +:a+, +:dpad_up+)
      #   @yieldparam pressed [Boolean] true if pressed, false if released
      #   @return [nil]

      # @!method self.on_axis {|instance_id, axis, value| ... }
      #   Register a callback for axis motion events.
      #   @yieldparam instance_id [Integer] SDL joystick instance ID
      #   @yieldparam axis [Symbol] axis name (e.g. +:left_x+, +:trigger_left+)
      #   @yieldparam value [Integer] axis value (-32768..32767 for sticks, 0..32767 for triggers)
      #   @return [nil]

      # @!method self.on_added {|device_index| ... }
      #   Register a callback for when a new gamepad is connected.
      #   @yieldparam device_index [Integer] device index (pass to {.open})
      #   @return [nil]

      # @!method self.on_removed {|instance_id| ... }
      #   Register a callback for when a gamepad is disconnected.
      #   @yieldparam instance_id [Integer] SDL joystick instance ID
      #   @return [nil]

      # @!endgroup

      # @!group Instance methods (C-defined)

      # @!method name
      #   Human-readable name of the controller (e.g. "Xbox One Controller").
      #   @return [String]

      # @!method attached?
      #   Whether the controller is still physically connected.
      #   @return [Boolean]

      # @!method button?(button)
      #   Whether the given button is currently pressed.
      #   @param button [Symbol] one of +:a+, +:b+, +:x+, +:y+, +:back+, +:guide+,
      #     +:start+, +:left_stick+, +:right_stick+, +:left_shoulder+,
      #     +:right_shoulder+, +:dpad_up+, +:dpad_down+, +:dpad_left+, +:dpad_right+
      #   @return [Boolean]

      # @!method axis(axis)
      #   Current value of an analog axis.
      #   @param axis [Symbol] one of +:left_x+, +:left_y+, +:right_x+, +:right_y+,
      #     +:trigger_left+, +:trigger_right+
      #   @return [Integer] -32768..32767 for sticks, 0..32767 for triggers

      # @!method instance_id
      #   SDL joystick instance ID. Useful for matching with event callbacks.
      #   @return [Integer]

      # @!method rumble(low_freq, high_freq, duration_ms)
      #   Trigger haptic feedback (rumble).
      #   @param low_freq [Integer] low-frequency motor intensity (0–65535)
      #   @param high_freq [Integer] high-frequency motor intensity (0–65535)
      #   @param duration_ms [Integer] duration in milliseconds
      #   @return [Boolean] true on success

      # @!method close
      #   Close the controller. Further method calls will raise.
      #   @return [nil]

      # @!method closed?
      #   Whether the controller has been closed.
      #   @return [Boolean]

      # @!method set_virtual_button(button, pressed)
      #   Set the state of a button on a virtual gamepad.
      #   @param button [Symbol] button name
      #   @param pressed [Boolean] true for pressed, false for released
      #   @return [nil]

      # @!method set_virtual_axis(axis, value)
      #   Set the value of an axis on a virtual gamepad.
      #   @param axis [Symbol] axis name
      #   @param value [Integer] axis value (-32768..32767 for sticks, 0..32767 for triggers)
      #   @return [nil]

      # @!endgroup

      # Analog stick axis range: -32768..32767 (centered at 0).
      AXIS_MIN = -32768
      AXIS_MAX =  32767

      # Trigger axis range: 0..32767 (0 = released, 32767 = fully pressed).
      TRIGGER_MIN = 0
      TRIGGER_MAX = 32767

      # Default dead zone threshold for analog sticks.
      # Values with absolute magnitude below this are treated as zero.
      DEAD_ZONE = 8000

      # Apply a dead zone to a stick axis value.
      # Returns 0 if the value is within the dead zone, otherwise
      # returns the original value.
      #
      # @param value [Integer] raw axis value (-32768..32767)
      # @param threshold [Integer] dead zone threshold
      # @return [Integer]
      def self.apply_dead_zone(value, threshold = DEAD_ZONE)
        value.abs < threshold ? 0 : value
      end
    end
  end
end
