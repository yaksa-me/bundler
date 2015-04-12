require 'bundler/fetcher/base'

module Bundler
  class Fetcher
    class Index < Base
      def specs(_gem_names)
        old_sources = Bundler.rubygems.sources
        Bundler.rubygems.sources = [remote_uri.to_s]
        Bundler.rubygems.fetch_all_remote_specs[remote_uri].map do |args|
          args = args.fill(nil, args.size..2)
          RemoteSpecification.new(*args, self)
        end
      rescue Gem::RemoteFetcher::FetchError, OpenSSL::SSL::SSLError => e
        case e.message
        when /certificate verify failed/
          raise CertificateFailureError.new(display_uri)
        when /401/
          raise AuthenticationRequiredError, remote_uri
        when /403/
          if remote_uri.userinfo
            raise BadAuthenticationError, remote_uri
          else
            raise AuthenticationRequiredError, remote_uri
          end
        else
          Bundler.ui.trace e
          raise HTTPError, "Could not fetch specs from #{display_uri}"
        end
      ensure
        Bundler.rubygems.sources = old_sources
      end

      def fetch_spec(spec)
        spec = spec - [nil, 'ruby', '']
        spec_file_name = "#{spec.join '-'}.gemspec"

        uri = URI.parse("#{remote_uri}#{Gem::MARSHAL_SPEC_DIR}#{spec_file_name}.rz")
        if uri.scheme == 'file'
          Bundler.load_marshal Gem.inflate(Gem.read_binary(uri.path))
        elsif cached_spec_path = gemspec_cached_path(spec_file_name)
          Bundler.load_gemspec(cached_spec_path)
        else
          Bundler.load_marshal Gem.inflate(downloader.fetch(uri).body)
        end
      rescue MarshalError
        raise HTTPError, "Gemspec #{spec} contained invalid data.\n" \
          "Your network or your gem server is probably having issues right now."
      end

      private

      # cached gem specification path, if one exists
      def gemspec_cached_path spec_file_name
        paths = Bundler.rubygems.spec_cache_dirs.map { |dir| File.join(dir, spec_file_name) }
        paths = paths.select {|path| File.file? path }
        paths.first
      end
    end
  end
end
