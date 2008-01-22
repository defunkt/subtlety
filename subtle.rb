# < subtlety 2 : a remote subversion (and hAtom) excursion' 
# > copyrite 2008 chris wanstrath
# < chris[at]ozmm[dot]org
# > MIT License 
%w( rubygems erb timeout sinatra sequel open3 ).each { |f| require f }

# hax.
class String;  def compact; gsub(/(\s{2,})/, ' ').gsub("\n", '') end end
module Kernel; def `(string) Open3.popen3(*string.split(' '))[1].read end end
class Integer; def minutes; self * 60 end; def ago; Time.now - self end end

def timeout(&block)
  Timeout.timeout(5, &block)
rescue Timeout::Error
  nil
end

##
# DB stuff
DB = Sequel('sqlite:/db/subtle.db')

class Item < Sequel::Model
  set_schema do
    primary_key :id
         string :url
        boolean :atom, :default => false
      timestamp :created_at
          index [ :url, :atom ]
  end

  def key
    pk.to_s(16)
  end

  def full_url
    "http://subtlety.errtheblog.com/O_o/#{key}.xml"
  end

  def self.find_or_create_by_url(url, atom = false)
    if model = self[:url => url, :atom => atom]
      return model
    end

    return unless url =~ /^(svn|http):\/\/(\w|\.|\/|-)+$/ && timeout { `/usr/bin/env svn info #{url}` =~ /Path:/ }

    create(:url => url, :created_at => Time.now, :atom => atom) 
  end
end

Item.set_dataset DB[:items]
Item.create_table unless Item.table_exists?

##
# actions / views
get '/' do
  index = %Q[
    <p class="first">
      Welcome.  Here's what we do: we take a remote, public subversion repository (http:// or svn://) and give you an rss feed of
      the changes.  That's it.  Have an <strong>svn:external</strong> or <strong><a href="http://piston.rubyforge.org/">pistonized</a></strong> 
      repository in your app you need to monitor?  Look no further: just plug in the repository's location and start reveling in the
      sweet, sweet changesets, rss-style.  
    </p>
    <p>
      The inaugural blog entry <a href="http://errtheblog.com/post/701">is here</a>.
    </p>
    <p>
      One thing: please add the repository's root path.  So, svn://errtheblog.com/svn/mofo, <strong>not</strong> 
      svn://errtheblog.com/svn/mofo/trunk.  Thanks, and enjoy.
    </p>
  ] << Helpers.form

  erb index 
end

post '/s' do
  url   = params[:feed].chomp('/')
  @item = Item.find_or_create_by_url(url)
  @rss  = "/O_o/#{@item.key}" if @item

  if @rss
    text = <<-end_html
    <p class="first">
      Here it is, your very own RSS feed of the changes committed to <strong>#{@item.url}</strong>:
    </p>
    <h3>
      <a href="#{@item.full_url}">#{@item.full_url}</a>
    </h3>
    &laquo; <a href="/">back home.</a>
    end_html
  else
    text = <<-end_html
    <p class="highlight">
      Sorry, there was some kind of error.  Are you sure your repository url's valid?  Does it start with svn:// or http://?
    </p>
    #{Helpers.form}
    end_html
  end

  erb text
end

get '/O_o/:key.xml' do 
  key = params[:key]
  @headers['Content-Type'] = 'application/xml'
  if File.exists?(@file = "feeds/#{key.gsub(/\W/,'')}.xml") && File.mtime(@file) > 15.minutes.ago
    sendfile @file
  else
    render_feed Item[:id => key.to_i(16)]
  end
end

def render_feed(item)
  tmp_file  = "/tmp/tmp-#{item.key}.xml"
  dir       = File.expand_path(File.dirname(__FILE__))
  erb_file  = "#{dir}/templates/svnlog.erb"
  xslt_file = "#{dir}/tmp/svnlog-#{item.key}.xslt"

  File.open(xslt_file, 'w') do |file|
    file.puts ERB.new(File.read(erb_file)).result(binding)
  end

  File.open(tmp_file, 'w') do |f|
    timeout do
      f.puts `/usr/bin/env svn log #{item.url.gsub(/ |\\|;/,'')} --limit 15 -v --xml`
    end
  end

  File.open(@file, 'w') do |f|
    timeout do
      f.puts `/usr/bin/env xsltproc #{xslt_file} #{tmp_file}`
    end
  end

  `rm #{tmp_file} #{xslt_file}`
  sendfile @file
end

config_for :development do
  def sendfile(file)
    return if file.include? '..'
    File.read(file)
  end

  get '/images/diag.gif' do
    @headers['Content-Type'] = 'image/gif'
    File.read('images/diag.gif')
  end 
end

config_for :production do
  def sendfile(file)
    return if file.include? '..'
    @headers['X-Accel-Redirect'] = "/static/#{file}"
  end
end

module Helpers
  extend self

  def clicky
    '<script src="http://getclicky.com/1149.js"> </script> <noscript><img height=0 width=0 src="http://getclicky.com/1149ns.gif"></noscript>'
  end

  def form
    <<-end_form
    <h3>create an rss feed from a public subversion repository:</h3>
    <form id="feed-me" method="post" action="/s">
      <p><input class="normal" type="text" name="feed" size="61" value="<%= @repository ? @repository.url : '' %>" /></p>
      <p><input type="submit" value="feed me."/></p>
    </form>
    end_form
  end

  def style
    style = %Q[
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

    "<style type='text/css'>#{style}</style>"
  end

  def footer
    links = [
      [ 'Sinatra',      "http://sinatra.rubyforge.org/" ],
      [ 'Sequel',       "http://sequel.rubyforge.org/" ],
      " and, to a lesser extent",
      [ 'Err the Blog', "http://errtheblog.com/" ]
    ]

    "Powered by " +
      links.map { |link| link.is_a?(Array) ? "<a href='#{link.last}'>#{link.first}</a>" : link }.join(", ") +
      "."
  end
end

layout do 
  <<-end_html
  <html>
    <head>
      #{Helpers.style}
      <% if @rss %>
        <link href="<%= @rss %>" rel="alternate" type="application/rss+xml"/>
      <% end %>
      <title>subtlety : a remote subversion and hAtom excursion</title>
    </head>
    <body>
      <div class="wrap">
        <div class="header">
          <h1>subtlety 2.</h1>
        </div>
        <div class="main">
          <%= yield.compact %>
        </div>
        <div class="footer">
          #{Helpers.footer}
        </div>
      </div>
      #{Helpers.clicky}
    </body>
  </html>
  end_html
end

