require File.dirname(__FILE__) + '/beanstream/beanstream_core'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    # This class implements the Canadian {Beanstream}[http://www.beanstream.com] payment gateway.
    # It is also named TD Canada Trust Online Mart payment gateway.
    # To learn more about the specification of Beanstream gateway, please read the OM_Direct_Interface_API.pdf,
    # which you can get from your Beanstream account or get from me by email.
    #  
    # == Supported transaction types by Beanstream:
    # * +P+ - Purchase
    # * +PA+ - Pre Authorization
    # * +PAC+ - Pre Authorization Completion
    #  
    # == Notes 
    # * Recurring billing is not yet implemented.
    # * Adding of order products information is not implemented.
    # * Ensure that country and province data is provided as a code such as "CA", "US", "QC".
    # * login is the Beanstream merchant ID, username and password should be enabled in your Beanstream account and passed in using the <tt>:user</tt> and <tt>:password</tt> options.
    # * Test your app with your true merchant id and test credit card information provided in the api pdf document.
    #  
    #  Example authorization (Beanstream PA transaction type):
    #  
    #   twenty = 2000
    #   gateway = BeanstreamGateway.new(
    #     :login => '100200000',
    #     :user => 'xiaobozz',
    #     :password => 'password'
    #   )
    #   
    #   credit_card = CreditCard.new(
    #     :number => '4030000010001234',
    #     :month => 8,
    #     :year => 2011,
    #     :first_name => 'xiaobo',
    #     :last_name => 'zzz',
    #     :verification_value => 137
    #   )
    #   response = gateway.authorize(twenty, credit_card,
    #     :order_id => '1234',
    #     :billing_address => {
    #       :name => 'xiaobo zzz',
    #       :phone => '555-555-5555',
    #       :address1 => '1234 Levesque St.',
    #       :address2 => 'Apt B',
    #       :city => 'Montreal',
    #       :state => 'QC',
    #       :country => 'CA',
    #       :zip => 'H2C1X8'
    #     },
    #     :email => 'xiaobozzz@example.com',
    #     :subtotal => 800,
    #     :shipping => 100,
    #     :tax1 => 100,
    #     :tax2 => 100,
    #     :custom => 'reference one'
    #   )
    class BeanstreamGateway < Gateway
      include BeanstreamCore
      
      def authorize(money, credit_card, options = {})
        post = {}
        add_amount(post, money)
        add_invoice(post, options)
        add_credit_card(post, credit_card)        
        add_address(post, options)
        add_transaction_type(post, :authorization)
        commit(post)
      end
      
      def purchase(money, source, options = {})
        post = {}
        add_amount(post, money) 
        add_invoice(post, options)
        add_source(post, source)
        add_address(post, options)
        add_transaction_type(post, purchase_action(source))
        commit(post)
      end                       
          
      def void(authorization, options = {})
        reference, amount, type = split_auth(authorization)
        
        post = {}
        add_reference(post, reference)
        add_original_amount(post, amount)
        add_transaction_type(post, void_action(type))
        commit(post)
      end
      
      def recurring(money, source, options = {})
        post = {}
        add_amount(post, money)
        add_invoice(post, options)
        add_credit_card(post, source)
        add_address(post, options)
        add_transaction_type(post, purchase_action(source))
        add_recurring_type(post, options)
        commit(post)
      end
      
      def update_recurring(amount, source, options = {})
        post = {}
        add_recurring_amount(post, amount)
        add_recurring_invoice(post, options)
        add_credit_card(post, source)
        add_address(post, options)
        add_recurring_operation_type(post, :update)
        add_recurring_service(post, options)
        recurring_commit(post)
      end
      
      def cancel_recurring(options = {})
        post = {}
        add_recurring_operation_type(post, :cancel)
        add_recurring_service(post, options)
        recurring_commit(post)
      end

      def transaction_report (options = {:start_year => Date.today.year, :start_month => Date.today.month, :start_day => Date.today.day,
                                         :end_year => Date.today.year, :end_month => Date.today.month, :end_day => Date.today.day})
        report_commit(prepare_search_params(options))
      end

      def today_report
        transaction_report()
      end

      
      def interac
        @interac ||= BeanstreamInteracGateway.new(@options)
      end

      def recurring_response_notification(response = {})
        make_recurring_response_notification(response)
      end
      
      private
      def build_response(*args)
        Response.new(*args)
      end
    end
  end
end

