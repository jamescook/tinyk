#!/usr/bin/env ruby
# frozen_string_literal: true
# teek-record: title=Calculator

# Calculator - A simple desktop calculator
#
# Run: ruby -Ilib sample/calculator.rb

require 'teek'

class Calculator
  attr_reader :app

  def initialize
    @app = Teek::App.new
    @display_value = '0'
    @pending_op = nil
    @accumulator = nil
    @reset_on_next = false

    build_ui
  end

  def build_ui
    @app.show
    @app.set_window_title('Calculator')
    @app.set_window_resizable(false, false)

    # Button style — use a larger font since macOS aqua theme
    # ignores vertical stretch; font size drives button height
    @app.tcl_eval('ttk::style configure Calc.TButton -font {{TkDefaultFont} 18}')

    # Display
    @app.set_variable('::display', '0')
    @display = @app.create_widget('ttk::entry', textvariable: '::display',
      justify: :right, state: :readonly, font: '{TkDefaultFont} 24')
    @display.grid(row: 0, column: 0, columnspan: 4,
      sticky: :ew, padx: 4, pady: 4, ipady: 8)

    build_buttons
  end

  def build_buttons
    # Row 1: C, +/-, %, /
    button('C',   1, 0, style: :accent) { clear }
    button('+/-', 1, 1, style: :accent) { negate }
    button('%',   1, 2, style: :accent) { percent }
    button('/',   1, 3, style: :op)     { set_op(:/) }

    # Row 2: 7, 8, 9, *
    button('7', 2, 0) { digit('7') }
    button('8', 2, 1) { digit('8') }
    button('9', 2, 2) { digit('9') }
    button('*', 2, 3, style: :op) { set_op(:*) }

    # Row 3: 4, 5, 6, -
    button('4', 3, 0) { digit('4') }
    button('5', 3, 1) { digit('5') }
    button('6', 3, 2) { digit('6') }
    button('-', 3, 3, style: :op) { set_op(:-) }

    # Row 4: 1, 2, 3, +
    button('1', 4, 0) { digit('1') }
    button('2', 4, 1) { digit('2') }
    button('3', 4, 2) { digit('3') }
    button('+', 4, 3, style: :op) { set_op(:+) }

    # Row 5: 0 (wide), ., =
    button('0', 5, 0, colspan: 2) { digit('0') }
    button('.', 5, 2) { decimal }
    button('=', 5, 3, style: :op) { equals }

    # Make columns equal width
    4.times { |c| @app.command(:grid, 'columnconfigure', '.', c, weight: 1, minsize: 60) }
  end

  # --- UI helpers ---

  # Click a button by its label (for demo/testing).
  # In recording mode, shows the pressed visual state briefly before invoking.
  def click(label, recording: false)
    widget = @buttons[label]
    return unless widget
    if recording
      widget.command('state', 'pressed')
      @app.after(80) {
        widget.command('state', '!pressed')
        widget.command(:invoke)
      }
    else
      widget.command(:invoke)
    end
  end

  def button(text, row, col, style: :num, colspan: 1, &action)
    @buttons ||= {}
    widget = @app.create_widget('ttk::button', text: text, style: 'Calc.TButton',
      command: proc { |*| action.call })
    @buttons[text] = widget
    widget.grid(row: row, column: col, columnspan: colspan,
      sticky: :nsew, padx: 2, pady: 2)
  end

  def update_display
    @app.set_variable('::display', @display_value)
  end

  # --- Calculator logic ---

  def digit(d)
    if @reset_on_next
      @display_value = '0'
      @reset_on_next = false
    end
    if @display_value == '0' && d != '0'
      @display_value = d
    elsif @display_value != '0'
      @display_value += d
    end
    update_display
  end

  def decimal
    @display_value = '0' if @reset_on_next
    @reset_on_next = false
    unless @display_value.include?('.')
      @display_value += '.'
    end
    update_display
  end

  def clear
    @display_value = '0'
    @pending_op = nil
    @accumulator = nil
    @reset_on_next = false
    update_display
  end

  def negate
    if @display_value.start_with?('-')
      @display_value = @display_value[1..]
    elsif @display_value != '0'
      @display_value = "-#{@display_value}"
    end
    update_display
  end

  def percent
    @display_value = (current_value / 100.0).to_s
    @reset_on_next = true
    update_display
  end

  def set_op(op)
    evaluate if @pending_op && !@reset_on_next
    @accumulator = current_value
    @pending_op = op
    @reset_on_next = true
  end

  def equals
    evaluate
    @pending_op = nil
  end

  def run
    @app.mainloop
  end

  private

  def current_value
    @display_value.to_f
  end

  def evaluate
    return unless @pending_op && @accumulator

    b = current_value
    result = case @pending_op
             when :+ then @accumulator + b
             when :- then @accumulator - b
             when :* then @accumulator * b
             when :/ then b.zero? ? Float::NAN : @accumulator / b
             end

    @accumulator = result
    @display_value = format_result(result)
    @reset_on_next = true
    update_display
  end

  def format_result(val)
    return 'Error' if val.nil? || val.nan? || val.infinite?
    val == val.to_i ? val.to_i.to_s : val.to_s
  end
end

calc = Calculator.new

# Automated demo support (testing and recording)
require_relative '../lib/teek/demo_support'
TeekDemo.app = calc.app

if TeekDemo.recording?
  calc.app.set_window_geometry('+0+0')
  calc.app.tcl_eval('. configure -cursor none')
  TeekDemo.signal_recording_ready
end

if TeekDemo.active?
  TeekDemo.after_idle {
    d = TeekDemo.method(:delay)
    app = calc.app
    rec = TeekDemo.recording?

    # Exercises all four operations, landing on 42.
    # 8 * 9 = 72, / 3 = 24, + 25 = 49, - 7 = 42
    steps = [
      -> { calc.click('8', recording: rec) },
      -> { calc.click('*', recording: rec) },
      -> { calc.click('9', recording: rec) },
      -> { calc.click('=', recording: rec) },      # 72
      nil,
      -> { calc.click('/', recording: rec) },
      -> { calc.click('3', recording: rec) },
      -> { calc.click('=', recording: rec) },      # 24
      nil,
      -> { calc.click('+', recording: rec) },
      -> { calc.click('2', recording: rec) },
      -> { calc.click('5', recording: rec) },
      -> { calc.click('=', recording: rec) },      # 49
      nil,
      -> { calc.click('-', recording: rec) },
      -> { calc.click('7', recording: rec) },
      -> { calc.click('=', recording: rec) },      # 42
      nil, nil,
      -> { TeekDemo.finish },
    ]

    run_step = nil
    i = 0
    run_step = proc {
      steps[i]&.call
      i += 1
      if i < steps.length
        app.after(d.call(test: 1, record: 250)) { run_step.call }
      end
    }
    run_step.call
  }
end

calc.run
