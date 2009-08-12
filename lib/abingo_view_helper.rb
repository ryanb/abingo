#Gives you easy syntax to use ABingo in your views.

module AbingoViewHelper

  def ab_test(test_name, alternatives = nil, options = {})
    if (alternatives.nil?)
      choice = Abingo.flip(test_name)
    else
      choice = Abingo.test(test_name, alternatives, options)
    end

    if block_given?
      yield(choice)
    else
      choice
    end
  end

  def ab_test(test_name, alternatives = nil, options = {}, &block)
    if (alternatives.nil?)
      choice = Abingo.flip(test_name)
    else
      choice = Abingo.test(test_name, alternatives, options)
    end
    content_tag = capture(choice, &block)
    block_called_from_erb?(block) ? concat(content_tag) : content_tag
  end

  def bingo!(test_name, options = {})
    Abingo.bingo!(test_name, options)
  end
  
end