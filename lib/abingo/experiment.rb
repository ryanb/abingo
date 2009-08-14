class Abingo::Experiment < ActiveRecord::Base
  include Abingo::Statistics
  include Abingo::ConversionRate

  has_many :alternatives, :dependent => :destroy
  validates_uniqueness_of :test_name

  def before_destroy
    Abingo.cache.delete("Abingo::Experiment::exists(#{test_name})".gsub(" ", ""))
  end

  def participants
    alternatives.sum("participants")
  end

  def conversions
    alternatives.sum("conversions")
  end

  def best_alternative
    alternatives.max do |a,b|
      a.conversion_rate <=> b.conversion_rate
    end
  end

  def chi_squared

    if alternatives.size == 0
      raise "Cannot calculate the chi-squared statistic of a test with no alternatives"
    end

    observed_table = Array.new(2)
    observed_table[0] = Array.new(alternatives.size) #Holds counts of non-converters
    observed_table[1] = Array.new(alternatives.size) #Holds counts of converters
    alternatives.each_with_index do |alt, i|
      observed_table[0][i] = alt.participants - alt.conversions
      observed_table[1][i] = alt.conversions
    end

    expected_table = Array.new(2)
    expected_table[0] = Array.new(alternatives.size) #Holds counts of non-converters
    expected_table[1] = Array.new(alternatives.size) #Holds counts of converters

    cr = conversion_rate

    alternatives.each_with_index do |alt, i|
      expected_table[0][i] = (1 - cr) * alternatives[i].participants  #expected non-converters
      expected_table[1][i] = (cr) * alternatives[i].participants  #expected converters
    end

    #Now we can actually calculate the chi-squared statistic: sum over all cells
    #in table, (actual - expected) ^ 2 / expected

    #First flatten them to save having to loop in two dimensions.
    observed_table.flatten!
    expected_table.flatten!

    chi = 0
    alternatives.each_with_index do |alt, i|
      chi += ((observed_table[i] - expected_table[i]) ** 2) / expected_table[i]
    end

    chi

  end

  #Determines the p value of the test.
  #Returns 1 for p value > .10, or the lowest of .05, .01, and .001 that we can
  #be sure is greater than the p value.
  def significance_test
    level = 1
    chi = chi_squared
    CHI_SQUARED_VALUES_FOR_STATISTICAL_SIGNIFICANCE.each do |p_val, threshhold|
      if ((chi > threshhold) && (p_val < level))
        level = p_val
      end
    end
    level
  end

  def self.exists?(test_name)
    cache_key = "Abingo::Experiment::exists(#{test_name})".gsub(" ", "")
    ret = Abingo.cache.fetch(cache_key) do
      count = Abingo::Experiment.count(:conditions => {:test_name => test_name})
      count > 0 ? count : nil
    end
    (!ret.nil?)
  end

  def self.alternatives_for_test(test_name)
    cache_key = "Abingo::#{test_name}::alternatives".gsub(" ","")
    Abingo.cache.fetch(cache_key) do
      experiment = Abingo::Experiment.find_by_test_name(test_name)
      alternatives_array = Abingo.cache.fetch(cache_key) do
        tmp_array = experiment.alternatives.map do |alt|
          [alt.content, alt.weight]
        end
        tmp_hash = tmp_array.inject({}) {|hash, couplet| hash[couplet[0]] = couplet[1]; hash}
        Abingo.parse_alternatives(tmp_hash)
      end
      alternatives_array
    end
  end

  def self.start_experiment!(test_name, alternatives_array)
    cloned_alternatives_array = alternatives_array.clone
    experiment = Abingo::Experiment.find_or_create_by_test_name(test_name)
    while (cloned_alternatives_array.size > 0)
      alt = cloned_alternatives_array[0]
      weight = cloned_alternatives_array.size - (cloned_alternatives_array - [alt]).size
      experiment.alternatives.create(:content => alt, :weight => weight,
        :lookup => Abingo::Alternative.calculate_lookup(test_name, alt))
      cloned_alternatives_array -= [alt]
    end
    Abingo.cache.delete("Abingo::Experiment::exists(#{test_name})".gsub(" ", ""))
    experiment
  end

end
