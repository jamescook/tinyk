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
