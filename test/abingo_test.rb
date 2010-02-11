require 'test_helper'

class AbingoTest < ActiveSupport::TestCase

  #Wipes cache, D/B prior to doing a test run.
  Abingo.cache.clear
  Abingo::Experiment.delete_all
  Abingo::Alternative.delete_all

  test "identity automatically assigned" do
    assert Abingo.identity != nil
  end

  test "alternative parsing" do
    array = %w{a b c}
    assert_equal array, Abingo.parse_alternatives(array)
    assert_equal 65, Abingo.parse_alternatives(65).size
    assert_equal 4, Abingo.parse_alternatives(2..5).size
    assert !(Abingo.parse_alternatives(2..5).include? 1)
  end

  test "experiment creation" do
    assert_equal 0, Abingo::Experiment.count
    assert_equal 0, Abingo::Alternative.count
    alternatives = %w{A B}
    alternative_selected = Abingo.test("unit_test_sample_A", alternatives)
    assert_equal 1, Abingo::Experiment.count
    assert_equal 2, Abingo::Alternative.count
    assert alternatives.include?(alternative_selected)
  end

  test "alternatives picked consistently" do
    alternative_picked = Abingo.test("consistency_test", 1..100)
    100.times do
      assert_equal alternative_picked, Abingo.test("consistency_test", 1..100)
    end
  end

  test "participation works" do
    new_tests = %w{participationA participationB participationC}
    new_tests.map do |test_name|
      Abingo.test(test_name, 1..5)
    end

    participating_tests = Abingo.cache.read("Abingo::participating_tests::#{Abingo.identity}") || []

    new_tests.map do |test_name|
      assert participating_tests.include? test_name
    end
  end

  test "participants counted" do
    test_name = "participants_counted_test"
    alternative = Abingo.test(test_name, %w{a b c})

    ex = Abingo::Experiment.find_by_test_name(test_name)
    lookup = Abingo::Alternative.calculate_lookup(test_name, alternative)
    chosen_alt = Abingo::Alternative.find_by_lookup(lookup)
    assert_equal 1, ex.participants
    assert_equal 1, chosen_alt.participants
  end

  test "conversion tracking by test name" do
    test_name = "conversion_test_by_name"
    alternative = Abingo.test(test_name, %w{a b c})
    Abingo.bingo!(test_name)
    ex = Abingo::Experiment.find_by_test_name(test_name)
    lookup = Abingo::Alternative.calculate_lookup(test_name, alternative)
    chosen_alt = Abingo::Alternative.find_by_lookup(lookup)
    assert_equal 1, ex.conversions
    assert_equal 1, chosen_alt.conversions
    Abingo.bingo!(test_name)

    #Should still only have one because this conversion should not be double counted.
    #We haven't specified that in the test options.
    assert_equal 1, Abingo::Experiment.find_by_test_name(test_name).conversions
  end

  test "conversion tracking by conversion name" do
    conversion_name = "purchase"
    tests = %w{conversionTrackingByConversionNameA conversionTrackingByConversionNameB conversionTrackingByConversionNameC}
    tests.map do |test_name|
      Abingo.test(test_name, %w{A B}, :conversion => conversion_name)
    end

    Abingo.bingo!(conversion_name)
    tests.map do |test_name|
      assert_equal 1, Abingo::Experiment.find_by_test_name(test_name).conversions
    end
  end
end
