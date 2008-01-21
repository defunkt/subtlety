# < subtlety : a remote subversion excursion' 
# > copyrite 2007 chris wanstrath
# < chris[at]ozmm[dot]org
# > MIT License 
%w(rubygems erb camping camping/db open3).each { |f| require f }

$debug = $0 =~ /camping/

# for defunkt. campistrano.
# ruby subtle.rb --update yourname@yourserver.com
if at = ARGV.index('--update')
  ssh = 'ssh ' << (ARGV[at+1] || 'chris@errtheblog.com')
  puts `#{ssh} 'cd sites/subtlety; svn up; rm feeds/*'`
  exec "#{ssh} 'sudo /etc/init.d/rv restart'"
end

Camping.goes :Subtle

# hax.
class String;  def compact; gsub(/(\s{2,})/, ' ').gsub("\n", '') end end
module Kernel; def `(string) Open3.popen3(*string.split(' '))[1].read end end

module Subtle::Models
  class GetReadyToParty < V 1.0
    def self.up
      create_table :subtle_repositories do |t|
        t.column :id,         :integer
        t.column :url,        :string
        t.column :created_at, :datetime
      end
    end

    def self.down 
      drop_table :repositories 
    end
  end

  class Repository < Base
    def validate
      errors.add("wrong format")  unless url =~ /^(svn|http):\/\/(\w|\.|\/|-)+$/
      errors.add("invalid repos") unless `/usr/bin/env svn info #{url}` =~ /Path:/
    end

    def key
      id.to_s(16)
    end
  end
end

module Subtle::Controllers
  class Index < R '/' 
    def get
      render :index
    end
  end

  class Save < R '/s'
    def post
      url         = input.feed.gsub(/\/$/,'')
      @repository = Repository.find_or_create_by_url(url)
      @rss        = R(Feed, @repository.key) if @repository.errors.blank?
      render :save
    end
  end

  class Feed < R '/O_o/(\w+).xml'
    def get(key)
      @headers['Content-Type'] = 'application/xml'
      if File.exists?(@file = "feeds/#{key.gsub(/\W/,'')}.xml") && File.mtime(@file) > 15.minutes.ago
        sendfile(@file)
      else
        @repository = Repository.find_by_id(key.to_i(16))
        render_feed
      end
    end

    def render_feed
      tmp_file  = "/tmp/tmp-#{@repository.key}.xml"
      dir       = File.expand_path(File.dirname(__FILE__))
      erb_file  = "#{dir}/svnlog.erb"
      xslt_file = "#{dir}/svnlog-#{@repository.key}.xslt"

       
      File.open(xslt_file, 'w') do |file|
        file.puts ERB.new(File.read(erb_file)).result(binding)
      end

      File.open(tmp_file, 'w') do |f|
        f.puts `/usr/bin/env svn log #{@repository.url.gsub(/ |\\|;/,'')} --limit 15 -v --xml`
      end

      File.open(@file, 'w') do |f|
        f.puts `/usr/bin/env xsltproc #{xslt_file} #{tmp_file}`
      end

      `rm #{tmp_file} #{xslt_file}`
      File.read(@file)
    end

    def sendfile(file)
      return if file.include? '..'

      return File.read(file)

      # TODO: cant get this working
      if $sendfile 
        # not implemented or tested, rly
        @headers['X-Sendfile'] = Pathname.new(__FILE__).dirname.realpath.to_s + file
      else
        # default to nginx
        @headers['X-Accel-Redirect'] = "/static/#{file}"
      end
    end
  end

  # dev mode only
  class Image < R '/images/diag.gif'
    def get
      @headers['Content-Type'] = 'image/gif'
      File.read('images/diag.gif')
    end
  end 
end

module Subtle::Views
  def layout
    html {
      head { 
        _style 
        if @rss
          link :href => @rss, :rel => "alternate", :type => "application/rss+xml"
        end
        title 'subtlety : a remote subversion excursion' 
      }
      body {
        div.wrap {
          div.header { h1 'subtlety.' }
          div.main { self << yield.compact }
          div.footer { _footer }
        }
        _clicky
      }
    }
  end

  def _clicky
    text '<script src="http://getclicky.com/1149.js"> </script> <noscript><img height=0 width=0 src="http://getclicky.com/1149ns.gif"></noscript>'
  end

  def index
    p.first { %Q[
      Welcome.  Here's what we do: we take a remote, public subversion repository (http:// or svn://) and give you an rss feed of
      the changes.  That's it.  Have an <strong>svn:external</strong> or <strong><a href="http://piston.rubyforge.org/">pistonized</a></strong> 
      repository in your app you need to monitor?  Look no further: just plug in the repository's location and start reveling in the
      sweet, sweet changesets, rss-style.  
    ] }
    p { %[The inaugural blog entry <a href="http://errtheblog.com/post/701">is here</a>.] }
    p { %Q[
      One thing: please add the repository's root path.  So, svn://errtheblog.com/svn/mofo, <strong>not</strong> 
      svn://errtheblog.com/svn/mofo/trunk.  Thanks, and enjoy.
    ] }
    _form
  end

  def save
    if @rss
      p.first text("Here it is, your very own RSS feed of the changes committed to <strong>#{@repository.url}</strong>:")
      url = R(Feed, @repository.key)
      h3 { a("http://subtlety.errtheblog.com#{url}", :href => url) }
      p text("&laquo; " + a("back home.", :href => '/'))
    else
      p.highlight "Sorry, there was some kind of error.  Are you sure your repository url's valid?  Does it start with svn:// or http://?"
      _form
    end
  end

  def _form
    h3 "create an rss feed from a public subversion repository:"
    form :id => 'feed-me', :method => 'post', :action => R(Save)  do
      p { input.normal :name => 'feed', :size => 61, :type => 'text', :value => @repository ? @repository.url : '' }
      p { input.submit :type => 'submit', :value => "feed me." }
    end
  end

  def _style
    style :type => "text/css" do
      %Q[
        body { background-color: #333; margin: 10px; font-family: arial, sans-serif; font-size: 13px; color: #333;
        background-image: url(/images/diag.gif); background-position: 760px; text-align: center; }
        div.wrap { width: 760px; text-align: left; margin: 0 auto; }
        a { text-decoration: none; color: #333; border-bottom: 1px solid #333; font-weight: bold; }
        a:hover { border-bottom: none; }
        div.header { background-color: #a7bc66; padding: 10px 10px 6px 10px; margin-bottom: 10px; text-align:right; }
        div.main { line-height: 150%; background-color: white; padding: 10px; margin-bottom: 10px; }
        div.footer { text-align: center; line-height: 150%; background-color: #999; padding: 10px; 
        margin-bottom: 10px; }
        div.main p { margin: 10px 0 0 0; }
        div.main p.first { margin-top: 0; }
        div.main p.title { font-size: 16px; font-weight: bold; margin-top: 0; }
        p.highlight { font-size: 2em; background: #999; padding: 10px; line-height: 120%; }
        .caps { font-size: 93%; text-transform: uppercase; }
        .desc { margin-left: 10px; padding: 10px; background-color: #ddd; line-height: 150%; }
        .desc .title { font-weight: bold; }
        .bar { margin-top: 10px; border-top: 1px solid #ccc; padding-top: 10px; }
        table { margin-bottom: 10px; }
        input.normal { font-size: 18px; font-weight: bold; padding: 5px; color: #a7bc66; border-color: #999999;
        border-width: 1px; border-style: solid; }
      ].compact
    end
  end

  def _footer
    text "Powered by "
    a 'Camping', :href => "http://code.whytheluckystiff.net/camping/"
    text ", "
    a 'Mongrel', :href => "http://mongrel.rubyforge.org/"            
    text " and, to a lesser extent, " 
    a 'Err the Blog', :href => "http://errtheblog.com/"
    text "."
  end
end

def Subtle.create
  Subtle::Models.create_schema
end
