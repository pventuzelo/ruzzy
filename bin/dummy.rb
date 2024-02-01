# frozen_string_literal: true

require 'ruzzy'

dummy_test_one_input = ->(data) { Ruzzy.dummy_test_one_input(data) }

Ruzzy.fuzz(dummy_test_one_input)
