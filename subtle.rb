# < subtlety 2 : a remote subversion (and hAtom) excursion' 
# > copyrite 2008 chris wanstrath
# < chris[at]ozmm[dot]org
# > MIT License 
%w( rubygems open-uri erb timeout sinatra sequel mofo open3 ).each { |f| require f }
gem 'mofo', '>= 0.2.11'
Mofo.timeout = 10

sessions :off

# hax.
class String;  def compact; gsub(/(\s{2,})/, ' ').gsub("\n", '') end end
module Kernel; def `(string) Open3.popen3(*string.split(' '))[1].read end end
class Integer; def minutes; self * 60 end; def ago; Time.now - self end end

def timeout(time = 5, &block)
  Timeout.timeout(time, &block)
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

  def key; pk.to_s(16) end
  def atom?; atom end
  def full_url; "http://subtlety.errtheblog.com/O_o/#{key}.xml" end

  def self.is_hAtom?(url)
    Array(hEntry.find(url)).any?
  end

  def self.is_svn?(url)
    timeout { `/usr/bin/env svn info #{url}` =~ /Path:/ }
  end

  def self.find_or_create_by_url(url)
    if model = self[:url => url]
      return model
    end

    return unless url =~ /^(svn|http):\/\/(\w|\.|\/|-)+$/ && (is_svn?(url) || atom = is_hAtom?(url))

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
      Welcome to Subtlety 2.  We do two, distinct things:
    </p>
    <ol>
      <li> Take a remote, public subversion repository (http:// or svn://) and produce an RSS feed of the changes. </li>
      <li> Take a page imbued with <a href="http://microformats.org/wiki/hatom">hAtom</a> and produce an equivalent Atom feed. </li>
    </ol>
    <p>
       Have an <strong>svn:external</strong> or <strong><a href="http://piston.rubyforge.org/">pistonized</a></strong> 
      repository in your app you need to monitor?  Look no further: plug in the repository's location and start reveling in the
      sweet, sweet changesets. 
    </p>
    <p>
      Hate the overhead of coding an RSS feed for your blog when the information is right there in the HTML?  We do, too.
      Plug in the hAtom'd URL, point something like Feedburner at it, then sit back and relax.
    <p>
      The inaugural blog entry <a href="http://errtheblog.com/post/701">is here</a>.
    </p>
    <p>
      (Oh, one thing: when going the SVN route, please add the repository's root path.  So, svn://errtheblog.com/svn/plugins, <strong>not</strong> 
      svn://errtheblog.com/svn/plugins/will_paginate.)
    </p>
    <p>
      Thanks, and enjoy.
    </p>
  ] << Helpers.form

  erb index 
end

post '/s' do
  url   = params[:feed].chomp('/')
  @item = Item.find_or_create_by_url(url)
  @rss  = @item.full_url if @item

  if @rss
    message = if @item.atom?
      "Here it is, your very own Atom feed from <strong>#{@item.url}</strong>: "
    else
      "Here it is, your very own RSS feed of the changes committed to <strong>#{@item.url}</strong>: "
    end

    text = <<-end_html
    <p class="first">#{message}</p>
    <h3> <a href="#{@item.full_url}">#{@item.full_url}</a> </h3>
    &laquo; <a href="/">back home.</a>
    end_html
  else
    text = <<-end_html
    <p class="highlight">
      Sorry, there was some kind of error.  Are you sure your url's valid?  Does it start with svn:// or http://?
    </p>
    #{Helpers.form}
    end_html
  end

  erb text
end

get '/O_o/:key.xml' do 
  key = params[:key]
  if File.exists?(@file = "feeds/#{key.gsub(/\W/,'')}.xml") && File.mtime(@file) > 15.minutes.ago
    sendfile @file
  else
    render_feed Item[:id => key.to_i(16)]
  end
end

def render_feed(item)
  item.atom? ? render_atom_feed(item) : render_svn_feed(item)
end

def render_svn_feed(item)
  tmp_file  = "/tmp/tmp-#{item.key}.xml"
  xslt_file = "/tmp/tmp-#{item.key}.xslt"
  erb_file  = "#{File.expand_path(File.dirname(__FILE__))}/templates/svnlog.erb"

  File.open(xslt_file, 'w') do |file|
    file.puts ERB.new(File.read(erb_file)).result(binding)
  end

  File.open(tmp_file, 'w') do |f|
    timeout { f.puts `/usr/bin/env svn log #{item.url.gsub(/ |\\|;/,'')} --limit 15 -v --xml` }
  end

  File.open(@file, 'w') do |f|
    timeout { f.puts `/usr/bin/env xsltproc #{xslt_file} #{tmp_file}` }
  end

  `rm #{tmp_file} #{xslt_file}`
  sendfile @file
end

def render_atom_feed(item)
  entries = hEntry.find(item.url)

  if entries.nil? || entries.empty?
    erb %(<h3>Error Atomizing #{item.url}!</h3><p>Couldn't find or parse hAtom.</p>)
  else
    feed = entries.to_atom.strip
    File.open(@file, 'w') { |f| f.puts feed }
    xml!
    feed
  end
end

def h(text)
  ERB::Util.h(text)
end

def xml!
  @headers['Content-Type'] = 'application/xml'
end

config_for :development do
  def sendfile(file)
    xml!
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
    xml!
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
    <h3> create a feed from a public subversion repository or hAtom'd page: </h3>
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
          <h1>subtlety two.</h1>
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
