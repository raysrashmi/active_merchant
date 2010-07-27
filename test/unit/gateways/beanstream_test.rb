#require File.dirname(__FILE__) + '/../../../../../../test/test_helper'
require File.dirname(__FILE__) + '/../../test_helper'


class BeanstreamTest < Test::Unit::TestCase
  def setup
    Base.mode = :test

    @gateway = BeanstreamGateway.new(
                                     :login => 'merchant id',
                                     :user => 'username',
                                     :password => 'password'
                                     )

    @credit_card = credit_card

    @check       = check(
                         :institution_number => '001',
                         :transit_number     => '26729'
                         )

    @amount = 1000

    @options = {
      :order_id => '1234',
      :billing_address => {
        :name => 'xiaobo zzz',
        :phone => '555-555-5555',
        :address1 => '1234 Levesque St.',
        :address2 => 'Apt B',
        :city => 'Montreal',
        :state => 'QC',
        :country => 'CA',
        :zip => 'H2C1X8'
      },
      :email => 'xiaobozzz@example.com',
      :subtotal => 800,
      :shipping => 100,
      :tax1 => 100,
      :tax2 => 100,
      :custom => 'reference one'
    }
    @recurring_options = @options.merge(
                                        :recurring_billing => {
                                          :first_billing => Date.today,
                                          :end_of_month => 0,
                                          :interval => {
                                            :unit => :months,
                                            :length => 1
                                          },
                                          :duration => {
                                            :start_date => Date.today,
                                            :occurrences => 5
                                          }
                                        }
                                        )
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal '10000028;15.00;P', response.authorization
  end
  
  def test_successful_test_request_in_production_environment
    Base.mode = :production
    @gateway.expects(:ssl_post).returns(successful_test_purchase_response)
    
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert response.test?
  end

  def test_unsuccessful_request
    @gateway.expects(:ssl_post).returns(unsuccessful_purchase_response)

    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
  end

  def test_avs_result
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_equal 'R', response.avs_result['code']
  end

  def test_ccv_result
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_equal 'M', response.cvv_result['code']
  end

  def test_successful_check_purchase
    @gateway.expects(:ssl_post).returns(successful_check_purchase_response)

    assert response = @gateway.purchase(@amount, @credit_card, @options)

    assert_success response
    assert_equal '10000072;15.00;D', response.authorization
    assert_equal 'Approved', response.message
  end

  def test_german_address_sets_state_to_the_required_dummy_value
    @gateway.expects(:commit).with(german_address_params_without_state)
    billing = @options[:billing_address]
    billing[:country]  = 'DE'
    billing[:city]     = 'Berlin'
    billing[:zip]      = '12345'
    billing[:state]    = nil
    @options[:shipping_address] = billing
    @gateway.purchase(@amount, @credit_card, @options)
  end
  def test_brazilian_address_sets_state_and_zip_to_the_required_dummy_values
    @gateway.expects(:commit).with(brazilian_address_params_without_zip_and_state)
    billing = @options[:billing_address]
    billing[:country]  = 'BR'
    billing[:city]     = 'Rio de Janeiro'
    billing[:zip]      = nil
    billing[:state]    = nil
    @options[:shipping_address] = billing

    @gateway.purchase(@amount, @credit_card, @options)
  end

  def test_successful_recurring
    @gateway.expects(:ssl_post).returns(successful_recurring_response)

    assert response = @gateway.recurring(@amount, @credit_card, @recurring_options)

    assert_success response
    assert_equal 'Approved', response.message
  end

  def test_successful_update_recurring
    @gateway.expects(:ssl_post).returns(successful_recurring_response)

    assert response = @gateway.recurring(@amount, @credit_card, @recurring_options)

    assert_success response
    assert_equal 'Approved', response.message

    @gateway.expects(:ssl_post).returns(successful_update_recurring_response)

    assert response = @gateway.update_recurring(@amount, @credit_card,@recurring_options.merge({:account_id => response.params["rbAccountId"]}))

    assert_success response
    assert_equal "Request successful", response.message
  end

  def test_successful_cancel_recurring
    @gateway.expects(:ssl_post).returns(successful_recurring_response)

    assert response = @gateway.recurring(@amount, @credit_card, @recurring_options)

    assert_success response
    assert_equal 'Approved', response.message

    @gateway.expects(:ssl_post).returns(successful_cancel_recurring_response)

    assert response = @gateway.cancel_recurring(:account_id => response.params["rbAccountId"])

    assert_success response
    assert_equal "Request successful", response.message
  end

  def test_parsing_transaction_report
    @gateway.expects(:ssl_post).returns(transaction_report_response)
    response = @gateway.transaction_report(
                                           :start_year => Date.today.year, :end_year => Date.today.year,
                                           :start_month => Date.today.month, :end_month => Date.today.month,
                                           :start_day => Date.today, :end_day => Date.today + 1
                                           )

    assert_equal 1, response.length
    assert_match response.first.params['trn_id'], transaction_report_response() 
    assert_equal '10000060', response.first.params['trn_id']
    assert_equal 'Neeraj Kumar', response.first.params['trn_card_owner']
    assert_equal 'nkumar@crri.co.in', response.first.params['b_email']
    assert_equal '210900000', response.first.params['merchant_id']
    assert_equal 'Approved', response.first.message

    assert_equal 'M',response.first.cvv_result['code']
    assert_equal 'Match',response.first.cvv_result['message']
  end

  def test_today_parsing_transaction_report
    @gateway.expects(:ssl_post).returns(today_transaction_report_response)
    response = @gateway.today_report()

    assert_equal 1, response.length
    assert_match response.first.params['trn_id'], today_transaction_report_response()
    assert_equal '10000060', response.first.params['trn_id']
    assert_equal 'Neeraj Kumar', response.first.params['trn_card_owner']
    assert_equal 'nkumar@crri.co.in', response.first.params['b_email']
    assert_equal '210900000', response.first.params['merchant_id']
    assert_equal 'Approved', response.first.message
    assert_equal 'M',response.first.cvv_result['code']
    assert_equal 'Match',response.first.cvv_result['message']
    assert_equal Date.today,response.first.params['trn_datetime'].to_date
  end

  def test_recurring_response_notification
    beanstream_response = {
      "billingIncrement"=>"1", "authCode"=>"TEST", "ref1"=>"", "billingId"=>"3991157",
      "trnId"=>"10000231", "messageId"=>"1", "periodFrom"=>"7/19/2010", "ref2"=>"",
      "orderNumber"=>"SOL30days1279290905", "accountName"=>"xiaobo zzz",
      "ref3"=>"", "ref4"=>"", "emailAddress"=>"nkumar@crri.co.in", "ref5"=>"",
      "billingPeriod"=>"D", "trnApproved"=>"1", "messageText"=>"Approved",
      "billingDate"=>"7/19/2010", "billingAmount"=>"20.00", "periodTo"=>"7/19/2010"
    }
    response = @gateway.recurring_response_notification(beanstream_response) 

    assert_not_nil response
    assert_equal response.params['trnId'], beanstream_response['trnId']
    assert_equal response.params['billingId'], beanstream_response['billingId']
    assert_equal response.params['messageId'], beanstream_response['messageId']
    assert_equal response.params['messageText'], beanstream_response['messageText']
    assert_equal response.params['periodFrom'], beanstream_response['periodFrom']
    assert_equal response.params['periodTo'], beanstream_response['periodTo']
    assert_equal response.params['orderNumber'], beanstream_response['orderNumber']
    assert_equal response.params['accountName'], beanstream_response['accountName']
    assert_equal response.params['emailAddress'], beanstream_response['emailAddress']
    assert_equal response.params['trnApproved'], beanstream_response['trnApproved']
    assert_equal response.params['billingDate'], beanstream_response['billingDate']
    assert_equal response.params['billingPeriod'], beanstream_response['billingPeriod']
    assert_equal response.params['billingAmount'], beanstream_response['billingAmount']
    assert_equal response.params['authCode'], beanstream_response['authCode']
  end

  private

  def successful_purchase_response
    "cvdId=1&trnType=P&trnApproved=1&trnId=10000028&messageId=1&messageText=Approved&trnOrderNumber=df5e88232a61dc1d0058a20d5b5c0e&authCode=TEST&errorType=N&errorFields=&responseType=T&trnAmount=15%2E00&trnDate=6%2F5%2F2008+5%3A26%3A53+AM&avsProcessed=0&avsId=0&avsResult=0&avsAddrMatch=0&avsPostalMatch=0&avsMessage=Address+Verification+not+performed+f"
  end

  def successful_test_purchase_response
    "merchant_id=100200000&trnId=11011067&authCode=TEST&trnApproved=1&avsId=M&cvdId=1&messageId=1&messageText=Approved&trnOrderNumber=1234"
  end

  def unsuccessful_purchase_response
    "merchant_id=100200000&trnId=11011069&authCode=&trnApproved=0&avsId=0&cvdId=6&messageId=16&messageText=Duplicate+transaction&trnOrderNumber=1234"
  end

  def successful_check_purchase_response

    "trnApproved=1&trnId=10000072&messageId=1&messageText=Approved&trnOrderNumber=5d9f511363a0f35d37de53b4d74f5b&authCode=&errorType=N&errorFields=&responseType=T&trnAmount=15%2E00&trnDate=6%2F4%2F2008+6%3A33%3A55+PM&avsProcessed=0&avsId=0&avsResult=0&avsAddrMatch=0&avsPostalMatch=0&avsMessage=Address+Verification+not+performed+for+this+transaction%2E&trnType=D&paymentMethod=EFT&ref1=reference+one&ref2=&ref3=&ref4=&ref5="
  end

  def brazilian_address_params_without_zip_and_state
    { :shipProvince => '--', :shipPostalCode => '000000', :ordProvince => '--', :ordPostalCode => '000000', :ordCountry => 'BR', :trnCardOwner => 'Longbob Longsen', :shipCity => 'Rio de Janeiro', :ordAddress1 => '1234 Levesque St.', :ordShippingPrice => '1.00', :deliveryEstimate => nil, :shipName => 'xiaobo zzz', :trnCardNumber => '4242424242424242', :trnAmount => '10.00', :trnType => 'P', :ordAddress2 => 'Apt B', :ordTax1Price => '1.00', :shipEmailAddress => 'xiaobozzz@example.com', :trnExpMonth => '09', :ordCity => 'Rio de Janeiro', :shipPhoneNumber => '555-555-5555', :ordName => 'xiaobo zzz', :trnExpYear => '11', :trnOrderNumber => '1234', :shipCountry => 'BR', :ordTax2Price => '1.00', :shipAddress1 => '1234 Levesque St.', :ordEmailAddress => 'xiaobozzz@example.com', :trnCardCvd => '123', :trnComments => nil, :shippingMethod => nil, :ref1 => 'reference one', :shipAddress2 => 'Apt B', :ordPhoneNumber => '555-555-5555', :ordItemPrice => '8.00' }
  end

  def german_address_params_without_state
    { :shipProvince => '--', :shipPostalCode => '12345', :ordProvince => '--', :ordPostalCode => '12345', :ordCountry => 'DE', :trnCardOwner => 'Longbob Longsen', :shipCity => 'Berlin', :ordAddress1 => '1234 Levesque St.', :ordShippingPrice => '1.00', :deliveryEstimate => nil, :shipName => 'xiaobo zzz', :trnCardNumber => '4242424242424242', :trnAmount => '10.00', :trnType => 'P', :ordAddress2 => 'Apt B', :ordTax1Price => '1.00', :shipEmailAddress => 'xiaobozzz@example.com', :trnExpMonth => '09', :ordCity => 'Berlin', :shipPhoneNumber => '555-555-5555', :ordName => 'xiaobo zzz', :trnExpYear => '11', :trnOrderNumber => '1234', :shipCountry => 'DE', :ordTax2Price => '1.00', :shipAddress1 => '1234 Levesque St.', :ordEmailAddress => 'xiaobozzz@example.com', :trnCardCvd => '123', :trnComments => nil, :shippingMethod => nil, :ref1 => 'reference one', :shipAddress2 => 'Apt B', :ordPhoneNumber => '555-555-5555', :ordItemPrice => '8.00' }
  end

  def successful_recurring_response
    "trnApproved=1&trnId=10000072&messageId=1&messageText=Approved&trnOrderNumber=5d9f511363a0f35d37de53b4d74f5b&authCode=&errorType=N&errorFields=&responseType=T&trnAmount=15%2E00&trnDate=6%2F4%2F2008+6%3A33%3A55+PM&avsProcessed=0&avsId=0&avsResult=0&avsAddrMatch=0&avsPostalMatch=0&avsMessage=Address+Verification+not+performed+for+this+transaction%2E&trnType=D&paymentMethod=EFT&ref1=reference+one&ref2=&ref3=&ref4=&ref5="
  end

  def successful_update_recurring_response
    "<response><code>1</code><message>Request successful</message></response>"
  end

  def successful_cancel_recurring_response
    "<response><code>1</code><message>Request successful</message></response>"
  end

  def transaction_report_response
    "merchant_id\tmerchant_name\ttrn_id\ttrn_datetime\ttrn_card_owner\ttrn_ip\ttrn_type\ttrn_amount\ttrn_original_amount\ttrn_returns\ttrn_order_number\ttrn_batch_number\ttrn_auth_code\ttrn_card_type\ttrn_adjustment_to\ttrn_response\tmessage_id\tb_name\tb_email\tb_phone\tb_address1\tb_address2\tb_city\tb_province\tb_postal\tb_country\ts_name\ts_email\ts_phone\ts_address1\ts_address2\ts_city\ts_province\ts_postal\ts_country\teci\tavs_response\tcvd_response\r\n210900000\tCastle Rock Research Corp\t10000060\t2010-07-13 01:50:13.883\tNeeraj Kumar\t220.227.120.161\tP\t2000\t2000\t0\tSOL30days1279011012\t193\tTEST  \tVI\t\t1\t1\txiaobo zzz\tnkumar@crri.co.in\t5147662333\t123 Rene-levesque St.\tApt B\tMontreal\tQC\tH4D1W9\tCA\t\000\t\000\t\000\t\000\t\000\t\000\t\000\t\000\t\000\t\t \t1"
  end

  def today_transaction_report_response
    "merchant_id\tmerchant_name\ttrn_id\ttrn_datetime\ttrn_card_owner\ttrn_ip\ttrn_type\ttrn_amount\ttrn_original_amount\ttrn_returns\ttrn_order_number\ttrn_batch_number\ttrn_auth_code\ttrn_card_type\ttrn_adjustment_to\ttrn_response\tmessage_id\tb_name\tb_email\tb_phone\tb_address1\tb_address2\tb_city\tb_province\tb_postal\tb_country\ts_name\ts_email\ts_phone\ts_address1\ts_address2\ts_city\ts_province\ts_postal\ts_country\teci\tavs_response\tcvd_response\r\n210900000\tCastle Rock Research Corp\t10000060\t#{Date.today}\tNeeraj Kumar\t220.227.120.161\tP\t2000\t2000\t0\tSOL30days1279011012\t193\tTEST  \tVI\t\t1\t1\txiaobo zzz\tnkumar@crri.co.in\t5147662333\t123 Rene-levesque St.\tApt B\tMontreal\tQC\tH4D1W9\tCA\t\000\t\000\t\000\t\000\t\000\t\000\t\000\t\000\t\000\t\t \t1"
  end

end

