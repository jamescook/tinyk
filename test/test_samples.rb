# frozen_string_literal: true

# Smoke tests for sample scripts.
# Each sample that supports TK_READY_PORT gets a test method here.
#
# To add a new sample test:
#   1. Add TeekDemo support to the sample (require teek/demo_support, use TeekDemo.on_visible/finish)
#   2. Add a test method here

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestSamples < Minitest::Test
  include TeekTestHelper

  SAMPLE_DIR = File.expand_path('../sample', __dir__)

  def test_goldberg
    success, stdout, stderr = smoke_test_sample("#{SAMPLE_DIR}/goldberg.rb", timeout: 30)

    assert success, "Goldberg demo failed\nSTDOUT: #{stdout}\nSTDERR: #{stderr}"
  end
end
