module ThreeScale
  module Backend
    module API
      internal_api '/services/:service_id/users' do
        module UserHelper
          def self.save(service_id, username, attributes, method, headers)
            halt 400, { status: :error, error: 'missing parameter \'user\'' }.to_json unless attributes
            attributes.merge!(service_id: service_id, username: username)
            begin
              user = User.save! attributes
            rescue => e
              [400, headers, { status: :error, error: e.message }.to_json]
            else
              post = method == :post
              [post ? 201 : 200, headers, { status: post ? :created : :modified, user: user.to_hash }.to_json]
            end
          end

          # XXX remove this once Core 1.5 is in production
          def self.old_core_client(useragent)
            useragent.nil? or useragent.empty? or useragent =~ /3scale_core v1\.[234]/
          end
        end

        get '/:username' do |service_id, username|
          user = User.load(service_id, username)
          if user
            { status: :found, user: user.to_hash }.to_json
          else
            [404, headers, { status: :not_found, error: 'user not found' }.to_json]
          end
        end

        post '/:username' do |service_id, username|
          UserHelper.save(service_id, username, params[:user], :post, headers)
        end

        put '/:username' do |service_id, username|
          UserHelper.save(service_id, username, params[:user], :put, headers)
        end

        delete '/:username' do |service_id, username|
          begin
            User.delete! service_id, username
            status = UserHelper.old_core_client(request.user_agent) ? :ok : :deleted
            { status: status }.to_json
          rescue => e
            [400, headers, { status: :error, error: e.message }.to_json]
          end
        end

      end
    end
  end
end