class Abingo::Experiment < ActiveRecord::Base
  include Abingo::Statistics
  include Abingo::ConversionRate

  has_many :alternatives, :dependent => :destroy
  validates_uniqueness_of :test_name

  def before_destroy
    Abingo.cache.delete("Abingo::Experiment::exists(#{test_name})".gsub(" ", ""))
    true
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
    ActiveRecord::Base.transaction do
      experiment = Abingo::Experiment.new(:test_name => test_name)
      while (cloned_alternatives_array.size > 0)
        alt = cloned_alternatives_array[0]
        weight = cloned_alternatives_array.size - (cloned_alternatives_array - [alt]).size
        experiment.alternatives.build(:content => alt, :weight => weight,
          :lookup => Abingo::Alternative.calculate_lookup(test_name, alt))
        cloned_alternatives_array -= [alt]
      end
      experiment.save!
      Abingo.cache.write("Abingo::Experiment::exists(#{test_name})".gsub(" ", ""), 1)
      experiment
    end
  end

end
