#This class is outside code's main interface into the ABingo A/B testing framework.
#Unless you're fiddling with implementation details, it is the only one you need worry about.

#Usage of ABingo, including practical hints, is covered at http://www.bingocardcreator.com/abingo

class Abingo

  #Not strictly necessary, but eh, as long as I'm here.
  cattr_accessor :salt
  @@salt = "Not really necessary."

  #ABingo stores whether a particular user has participated in a particular
  #experiment yet, and if so whether they converted, in the cache.
  #
  #It is STRONGLY recommended that you use a MemcacheStore for this.
  #If you'd like to persist this through a system restart or the like, you can
  #look into memcachedb, which speaks the memcached protocol.  From the perspective
  #of Rails it is just another MemcachedStore.
  #
  #You can overwrite Abingo's cache instance, if you would like it to not share
  #your generic Rails cache.
  cattr_writer :cache

  def self.cache
    @@cache || Rails.cache
  end

  #This method gives a unique identity to a user.  It can be absolutely anything
  #you want, as long as it is consistent.
  #
  #We use the identity to determine, deterministically, which alternative a user sees.
  #This means that if you use Abingo.identify_user on someone at login, they will
  #always see the same alternative for a particular test which is past the login
  #screen.  For details and usage notes, see the docs.
  def self.identity=(new_identity)
    @@identity = new_identity.to_s
  end

  def self.identity
    @@identity ||= rand(10 ** 10).to_i.to_s
  end

  #A simple convenience method for doing an A/B test.  Returns true or false.
  #If you pass it a block, it will bind the choice to the variable given to the block.
  def self.flip(test_name)
    if block_given?
      yield(self.test(test_name, [true, false]))
    else
      self.test(test_name, [true, false])
    end
  end

  #This is the meat of A/Bingo.
  def self.test(test_name, alternatives, options = {})
    unless Abingo::Experiment.exists?(test_name)
      Abingo::Experiment.start_experiment!(test_name, self.parse_alternatives(alternatives))
    end

    choice = self.find_alternative_for_user(test_name, alternatives)
    participating_tests = Abingo.cache.read("Abingo::participating_tests::#{Abingo.identity}") || []
    
    #Set this user to participate in this experiment, and increment participants count.
    if options[:multiple_participation] || !(participating_tests.include?(test_name))
      unless participating_tests.include?(test_name)
        participating_tests << test_name
        Abingo.cache.write("Abingo::participating_tests::#{Abingo.identity}", participating_tests)
      end
      Abingo::Alternative.score_participation(test_name)
    end

    if block_given?
      yield(choice)
    else
      choice
    end
  end


  def Abingo.bingo!(test_name_or_array = nil, options = {})
    if test_name_or_array.kind_of? Array
      test_name_or_array.map do |single_test|
        self.bingo!(single_test, options)
      end
    else
      participating_tests = Abingo.cache.read("Abingo::participating_tests::#{Abingo.identity}") || []
      if test_name_or_array.nil?
        participating_tests.each do |participating_test|
          self.bingo!(participating_test, options)
        end
      else #Individual, non-nil test is named
        test_name_str = test_name_or_array.to_s
        if options[:assume_participation] || participating_tests.include?(test_name_str)
          cache_key = "Abingo::conversions(#{Abingo.identity},#{test_name_str}"
          if options[:multiple_conversions] || !Abingo.cache.read(cache_key)
            Abingo::Alternative.score_conversion(test_name_str)
            if Abingo.cache.exist?(cache_key)
              Abingo.cache.increment(cache_key)
            else
              Abingo.cache.write(cache_key, 1)
            end
          end
        end
      end
    end
  end

  #For programmer convenience, we allow you to specify what the alternatives for
  #an experiment are in a few ways.  Thus, we need to actually be able to handle
  #all of them.  We fire this parser very infrequently (once per test, typically)
  #so it can be as complicated as we want.
  #   Integer => a number 1 through N
  #   Range   => a number within the range
  #   Array   => an element of the array.
  #   Hash    => assumes a hash of something to int.  We pick one of the 
  #              somethings, weighted accorded to the ints provided.  e.g.
  #              {:a => 2, :b => 3} produces :a 40% of the time, :b 60%.
  #
  #Alternatives are always represented internally as an array.
  def self.parse_alternatives(alternatives)
    if alternatives.kind_of? Array
      return alternatives
    elsif alternatives.kind_of? Integer
      return (1..alternatives).to_a
    elsif alternatives.kind_of? Range
      return alternatives.to_a
    elsif alternatives.kind_of? Hash
      alternatives_array = []
      alternatives.each do |key, value|
        if value.kind_of? Integer
          alternatives_array += [key] * value
        else
          raise "You gave an array with #{value} as a value.  It needed to be an integer."
        end
      end
      return alternatives_array
    else
      raise "I don't know how to turn [#{alternatives}] into an array of alternatives."
    end
  end

  def self.retrieve_alternatives(test_name, alternatives)
    cache_key = "Abingo::#{test_name}::alternatives".gsub(" ","")
    alternative_array = self.cache.fetch(cache_key) do
      self.parse_alternatives(alternatives)
    end
    alternative_array
  end

  def self.find_alternative_for_user(test_name, alternatives)
    alternatives_array = retrieve_alternatives(test_name, alternatives)
    alternatives_array[self.modulo_choice(test_name, alternatives_array.size)]
  end

  #Quickly determines what alternative to show a given user.  Given a test name
  #and their identity, we hash them together (which, for MD5, provably introduces
  #enough entropy that we don't care) otherwise
  def self.modulo_choice(test_name, choices_count)
    Digest::MD5.hexdigest(Abingo.salt.to_s + test_name + self.identity.to_s).to_i(16) % choices_count
  end

end