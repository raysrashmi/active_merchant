module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    module BeanstreamCore
      URL = 'https://www.beanstream.com/scripts/process_transaction.asp'
      RECURRING_URL = 'https://www.beanstream.com/scripts/recurring_billing.asp'
      REPORT_URL = 'https://www.beanstream.com/scripts/report_download.asp'

      TRANSACTIONS = {
              :authorization  => 'PA',
              :purchase       => 'P',
              :capture        => 'PAC',
              :credit         => 'R',
              :void           => 'VP',
              :check_purchase => 'D',
              :check_credit   => 'C',
              :void_purchase  => 'VP',
              :void_credit    => 'VR'
      }

      CVD_CODES = {
              '1' => 'M',
              '2' => 'N',
              '3' => 'I',
              '4' => 'S',
              '5' => 'U',
              '6' => 'P'
      }

      AVS_CODES = {
              '0' => 'R',
              '5' => 'I',
              '9' => 'I'
      }

      PERIOD = {
              :days => 'D',
              :weeks => 'W',
              :months => 'M',
              :years => 'Y'
      }

      def self.included(base)
        base.default_currency = 'CAD'

        # The countries the gateway supports merchants from as 2 digit ISO country codes
        base.supported_countries = ['CA']

        # The card types supported by the payment gateway
        base.supported_cardtypes = [:visa, :master, :american_express]

        # The homepage URL of the gateway
        base.homepage_url = 'http://www.beanstream.com/'

        # The name of the gateway
        base.display_name = 'Beanstream.com'
      end
      # Only <tt>:login</tt> is required by default, 
      # which is the merchant's merchant ID. If you'd like to perform void, 
      # capture or credit transactions then you'll also need to add a username
      # and password to your account under administration -> account settings ->
      # order settings -> Use username/password validation
      def initialize(options = {})
        requires!(options, :login)
        @options = options
        super
      end
      def capture(money, authorization, options = {})
        reference, amount, type = split_auth(authorization)

        post = {}
        add_amount(post, money)
        add_reference(post, reference)
        add_transaction_type(post, :capture)
        commit(post)
      end
      def credit(money, source, options = {})
        post = {}
        reference, amount, type = split_auth(source)
        add_reference(post, reference)
        add_transaction_type(post, credit_action(type))
        add_amount(post, money)
        commit(post)
      end
      private
      def purchase_action(source)
        card_brand(source) == "check" ? :check_purchase : :purchase
      end

      def void_action(original_transaction_type)
        original_transaction_type == TRANSACTIONS[:credit] ? :void_credit : :void_purchase
      end

      def credit_action(type)
        type == TRANSACTIONS[:check_purchase] ? :check_credit : :credit
      end

      def split_auth(string)
        string.split(";")
      end

      def add_amount(post, money)
        post[:trnAmount] = amount(money)
      end

      def add_original_amount(post, amount)
        post[:trnAmount] = amount
      end

      def add_reference(post, reference)
        post[:adjId] = reference
      end

      def add_address(post, options)
        prepare_address_for_non_american_countries(options)

        if billing_address = options[:billing_address] || options[:address]
          post[:ordName]          = billing_address[:name]
          post[:ordEmailAddress]  = options[:email]
          post[:ordPhoneNumber]   = billing_address[:phone]
          post[:ordAddress1]      = billing_address[:address1]
          post[:ordAddress2]      = billing_address[:address2]
          post[:ordCity]          = billing_address[:city]
          post[:ordProvince]      = billing_address[:state]
          post[:ordPostalCode]    = billing_address[:zip]
          post[:ordCountry]       = billing_address[:country]
        end
        if shipping_address = options[:shipping_address]
          post[:shipName]         = shipping_address[:name]
          post[:shipEmailAddress] = options[:email]
          post[:shipPhoneNumber]  = shipping_address[:phone]
          post[:shipAddress1]     = shipping_address[:address1]
          post[:shipAddress2]     = shipping_address[:address2]
          post[:shipCity]         = shipping_address[:city]
          post[:shipProvince]     = shipping_address[:state]
          post[:shipPostalCode]   = shipping_address[:zip]
          post[:shipCountry]      = shipping_address[:country]
          post[:shippingMethod]   = shipping_address[:shipping_method]
          post[:deliveryEstimate] = shipping_address[:delivery_estimate]
        end
      end

      def prepare_address_for_non_american_countries(options)
        [ options[:billing_address], options[:shipping_address] ].compact.each do |address|
          unless ['US', 'CA'].include?(address[:country])
            address[:state] = '--'
            address[:zip]   = '000000' unless address[:zip]
          end
        end
      end

      def add_invoice(post, options)
        post[:trnOrderNumber]   = options[:order_id]
        post[:trnComments]      = options[:description]
        post[:ordItemPrice]     = amount(options[:subtotal])
        post[:ordShippingPrice] = amount(options[:shipping])
        post[:ordTax1Price]     = amount(options[:tax1] || options[:tax])
        post[:ordTax2Price]     = amount(options[:tax2])
        post[:ref1]             = options[:custom]
      end
      def add_credit_card(post, credit_card)
        post[:trnCardOwner] = credit_card.name
        post[:trnCardNumber] = credit_card.number
        post[:trnExpMonth] = format(credit_card.month, :two_digits)
        post[:trnExpYear] = format(credit_card.year, :two_digits)
        post[:trnCardCvd] = credit_card.verification_value
      end

      def add_check(post, check)
        # The institution number of the consumer’s financial institution. Required for Canadian dollar EFT transactions.
        post[:institutionNumber] = check.institution_number

        # The bank transit number of the consumer’s bank account. Required for Canadian dollar EFT transactions.
        post[:transitNumber] = check.transit_number

        # The routing number of the consumer’s bank account.  Required for US dollar EFT transactions.
        post[:routingNumber] = check.routing_number

        # The account number of the consumer’s bank account.  Required for both Canadian and US dollar EFT transactions.
        post[:accountNumber] = check.account_number
      end

      def add_recurring_amount(post, money)
        post[:amount] = amount(money)
      end

      def add_recurring_invoice(post, options)
        post[:rbApplyTax1] = options[:apply_tax1]
      end

      def add_recurring_operation_type(post, operation)
        post[:operationType] = if operation == :update
          'M'
        elsif operation == :cancel
          'C'
        end
      end

      def add_recurring_service(post, options)
        post[:serviceVersion] = '1.0'
        post[:merchantId]     = @options[:login]
        post[:passCode]       = @options[:pass_code]
        post[:rbAccountId]    = options[:account_id]
      end

      def add_recurring_type(post, options)
        recurring_options         = options[:recurring_billing]
        post[:trnRecurring]       = '1'
        post[:rbBillingPeriod]    = PERIOD[recurring_options[:interval][:unit]]
        post[:rbBillingIncrement] = recurring_options[:interval][:length]
        post[:rbFirstBilling]     = recurring_options[:duration][:start_date].strftime("%m%d%Y")
        post[:rbExpiry]           = (recurring_options[:duration][:start_date] >> recurring_options[:duration][:occurrences]).strftime("%m%d%Y")
        post[:rbEndMonth]         = recurring_options[:end_of_month] if recurring_options[:end_of_month]
        post[:rbApplyTax1]        = recurring_options[:tax1] if recurring_options[:tax1]
      end

      def parse(body)
        results = {}
        if !body.nil?
          body.split(/&/).each do |pair|
            key, val = pair.split(/=/)
            results[key.to_sym] = val.nil? ? nil : CGI.unescape(val)
          end
        end

        # Clean up the message text if there is any
        if results[:messageText]
          results[:messageText].gsub!(/<LI>/, "")
          results[:messageText].gsub!(/(\.)?<br>/, ". ")
          results[:messageText].strip!
        end

        results
      end

      def recurring_parse(data)
        response = {}
        xml = REXML::Document.new(data)
        root = REXML::XPath.first(xml, "response")

        root.elements.to_a.each do |node|
          recurring_parse_element(response, node)
        end

        response
      end

      def recurring_parse_element(response, node)
        if node.has_elements?
          node.elements.each{|e| recurring_parse_element(response, e) }
        else
          response[node.name.underscore.to_sym] = node.text
        end
      end

      def to_hash(row, header)
        transaction_hash = {}
        row.each_with_index {|column_value, index| transaction_hash[header[index]] = column_value }
        transaction_hash
      end

      def parse_transaction_report(response_body)
        transaction_rows = FasterCSV.new(response_body, {:col_sep => "\t"}).read
        transaction_reports = []
        header = transaction_rows.shift(1)
        header.flatten!
        transaction_rows.each do |row|
          transaction_reports.push(to_hash(row, header)) unless row.empty?
        end

        transaction_reports
      end

      def commit(params)
        post(post_data(params))
      end

      def recurring_commit(params)
        recurring_post(post_data(params))
      end

      def post(data)
        response = parse(ssl_post(URL, data))
        build_response(success?(response), message_from(response), response,
                       :test => test? || response[:authCode] == "TEST",
                       :authorization => authorization_from(response),
                       :cvv_result => CVD_CODES[response[:cvdId]],
                       :avs_result => { :code => (AVS_CODES.include? response[:avsId]) ? AVS_CODES[response[:avsId]] : response[:avsId] }
        )
      end

      def recurring_post(data)
        response = recurring_parse(ssl_post(RECURRING_URL, data))
        build_response(recurring_success?(response), recurring_message_from(response), response,
                       :test => test? || response[:authCode] == "TEST",
                       :authorization => recurring_authorization_from(response),
                       :cvv_result => CVD_CODES[response[:cvdId]],
                       :avs_result => { :code => (AVS_CODES.include? response[:avsId]) ? AVS_CODES[response[:avsId]] : response[:avsId] }
        )
      end

      def make_recurring_response_notification(response)
         build_response(success?(response), message_from(response), response,
                       :test => test? || response[:authCode] == "TEST",
                       :authorization => authorization_from(response),
                       :cvv_result => CVD_CODES[response[:cvdId]],
                       :avs_result => { :code => (AVS_CODES.include? response[:avsId]) ? AVS_CODES[response[:avsId]] : response[:avsId] }
        )
      end

      def authorization_from(response)
        "#{response[:trnId]};#{response[:trnAmount]};#{response[:trnType]}"
      end

      def recurring_authorization_from(response)
        response[:account_id]
      end

      def transaction_authorization_from(response)
        "#{response['trn_id']};#{response['trn_amount']};#{response['trn_type']}"
      end

      def message_from(response)
        response[:messageText]
      end

      def transaction_message(response)
        case response['trn_response']
          when '0'
            return 'In Process'
          when '1'
            return 'Approved'
          when '2'
            return 'Declined'
          when '3'
            return 'Not Processed'
          else
            return "Unknown transaction message received!! : #{response['trn_response']}"
        end
      end


      def recurring_message_from(response)
        response[:message]
      end

      def success?(response)
        response[:responseType] == 'R' || response[:trnApproved] == '1'
      end

      def transaction_approved?(response)
        response['trn_response'] == '1'
      end

      def recurring_success?(response)
        response[:code] == '1'
      end

      def add_source(post, source)
        card_brand(source) == "check" ? add_check(post, source) : add_credit_card(post, source)
      end

      def add_transaction_type(post, action)
        post[:trnType] = TRANSACTIONS[action]
      end

      def post_data(params)
        params[:requestType] = 'BACKEND'
        params[:merchant_id] = @options[:login]
        params[:username] = @options[:user] if @options[:user]
        params[:password] = @options[:password] if @options[:password]
        params[:vbvEnabled] = '0'
        params[:scEnabled] = '0'

        params.reject{|k, v| v.blank?}.collect { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join("&")
      end

      def report_commit(params)
        get_transaction_report(add_transaction_report_params(params))
      end

      def get_transaction_report(data)
        transaction_response = parse_transaction_report(ssl_post(REPORT_URL, data))
        responses = transaction_response.map do |response|
          build_response(transaction_approved?(response), transaction_message(response), response,
                         :test => test? || response[:authCode] == "TEST",
                         :authorization => transaction_authorization_from(response),
                         :cvv_result => CVD_CODES[response['cvd_response']],
                         :avs_result => { :code => (AVS_CODES.include? response['avs_response']) ? AVS_CODES[response['avs_response']] : response['avs_response'] }
          )
        end

        responses
      end


      def prepare_search_params(options)
        params = {}
        params[:rptStartYear]  =  options[:start_year]
        params[:rptStartMonth] =  options[:start_month]
        params[:rptStartDay]   =  options[:start_day]
        params[:rptEndYear]    =  options[:end_year]
        params[:rptEndMonth]   =  options[:end_month]
        params[:rptEndDay]     =  options[:end_day]
        params[:rptStatus]     =  options[:status]
        params[:rptCardType]   =  options[:card_type]
        params[:rptTransTypes] =  options[:trans_type]
        params[:rptRef]        =  options[:ref]
        params[:rptBatchNumber] = options[:batch_number]
        params[:rptRange] =       options[:range]
        params[:rptIdStart] =     options[:start_id]
        params[:rptIdEnd] =       options[:end_id]
        params[:rptNoFile] =      options[:no_file]

        params
      end

      def add_transaction_report_params(params)
        params[:requestType] = 'BACKEND'
        params[:loginCompany] = @options[:login]
        params[:loginUser] = @options[:user] if @options[:user]
        params[:loginPass] = @options[:password] if @options[:password]
        params[:vbvEnabled] = '0'
        params[:scEnabled] = '0'
        params[:rptNoFile]=0
        params[:rptVersion] = 1.6

        params.reject{|k, v| v.blank?}.collect { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join("&")
      end
    end
  end
end

