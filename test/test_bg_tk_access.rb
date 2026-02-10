# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestBgTkAccess < Minitest::Test
  include TeekTestHelper

  def test_referencing_app_in_ractor_block_raises_isolation_error
    assert_tk_app("referencing app in Ractor work block should raise IsolationError") do
      skip "Ractor not supported" unless Teek::BackgroundWork::RACTOR_SUPPORTED

      # Assign to local so the block closes over it (method calls via
      # instance_eval don't create closure captures).
      my_app = app

      err = assert_raises(Ractor::IsolationError) do
        Teek::BackgroundWork.new(my_app, ['test'], mode: :ractor) do |t, data|
          my_app.tcl_eval("puts hello")
        end.on_progress { |msg| }.on_done { }
      end

      assert_match(/must not reference outside variables/, err.message)
    end
  end
end
