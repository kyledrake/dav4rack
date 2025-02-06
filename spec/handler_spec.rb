require "spec_helper"
require "webrick/httputils"
require "debug"

RSpec.describe DAV4Rack::Handler do
  DOC_ROOT = File.expand_path("htdocs", __dir__)
  METHODS = %w(GET PUT POST DELETE PROPFIND PROPPATCH MKCOL COPY MOVE OPTIONS HEAD LOCK UNLOCK)  
  
  before do
    FileUtils.mkdir(DOC_ROOT) unless File.exist?(DOC_ROOT)
    @controller = DAV4Rack::Handler.new(:root => DOC_ROOT)
  end

  after do
    FileUtils.rm_rf(DOC_ROOT) if File.exist?(DOC_ROOT)
  end
  
  attr_reader :response
  
  def request(method, uri, options = {})
    options = {
      'HTTP_HOST' => 'localhost',
      'rack.input' => StringIO.new(options.delete(:input) || ''), # Ensure a proper request body
    }.merge(options)

    request = Rack::MockRequest.new(@controller)
    @response = request.request(method, uri, **options)
  end

  METHODS.each do |method|
    define_method(method.downcase) do |*args|
      request(method, *args)
    end
  end  
  
  def render(root_type)
    raise ArgumentError.new 'Expecting block' unless block_given?
    doc = Nokogiri::XML::Builder.new do |xml_base|
      xml_base.send(root_type.to_s, 'xmlns:D' => 'DAV:') do
        xml_base.parent.namespace = xml_base.parent.namespace_definitions.first
        xml = xml_base['D']
        yield xml
      end
    end
    doc.to_xml
  end
 
  def url_escape(string)
    WEBrick::HTTPUtils.escape(string)
  end
  
  def response_xml
    Nokogiri.XML(@response.body)
  end
  
  def multistatus_response(pattern)
    expect(@response).to be_multi_status
    expect(response_xml.xpath('//D:multistatus/D:response', response_xml.root.namespaces)).not_to be_empty
    response_xml.xpath("//D:multistatus/D:response#{pattern}", response_xml.root.namespaces)    
  end

  def multi_status_created
    expect(response_xml.xpath('//D:multistatus/D:response/D:status')).not_to be_empty
    expect(response_xml.xpath('//D:multistatus/D:response/D:status').text).to match(/Created/)
  end
  
  def multi_status_ok
    expect(response_xml.xpath('//D:multistatus/D:response/D:status')).not_to be_empty
    expect(response_xml.xpath('//D:multistatus/D:response/D:status').text).to match(/OK/)
  end
  
  def multi_status_no_content
    expect(response_xml.xpath('//D:multistatus/D:response/D:status')).not_to be_empty
    expect(response_xml.xpath('//D:multistatus/D:response/D:status').text).to match(/No Content/)
  end
  
  def propfind_xml(*props)
    render(:propfind) do |xml|
      xml.prop do
        props.each do |prop|
          xml.send(prop)
        end
      end
    end
  end
  
  it 'returns all options' do
    expect(options('/')).to be_ok
    
    METHODS.each do |method|
      expect(response.headers['allow']).to include(method)
    end
  end
  
  it 'returns headers' do
    expect(put('/test.html', :input => '<html/>')).to be_created
    expect(head('/test.html')).to be_ok
    
    expect(response.headers['etag']).not_to be_nil
    expect(response.headers['content-type']).to match(/html/)
    expect(response.headers['last-modified']).not_to be_nil
  end
  
  it 'does not find a nonexistent resource' do
    expect(get('/not_found')).to be_not_found
  end
  
  it 'does not allow directory traversal' do
    expect(get('/../htdocs')).to be_forbidden
  end
  
  it 'creates a resource and allow its retrieval' do
    expect(put('/test', :input => 'body')).to be_created
    expect(get('/test')).to be_ok

    expect(response.body).to eq('body')
  end

  it 'returns an absolute url after a put request' do
    expect(put('/test', :input => 'body')).to be_created
    expect(response['location']).to match(/http:\/\/localhost(:\d+)?\/test/)
  end
  
  it 'creates and finds a url with escaped characters' do
    expect(put(url_escape('/a b'), :input => 'body')).to be_created
    expect(get(url_escape('/a b'))).to be_ok
    expect(response.body).to eq('body')
  end
  
  it 'deletes a single resource' do
    expect(put('/test', :input => 'body')).to be_created
    expect(delete('/test')).to be_no_content
  end
  
  it 'deletes recursively' do
    expect(mkcol('/folder')).to be_created
    expect(put('/folder/a', :input => 'body')).to be_created
    expect(put('/folder/b', :input => 'body')).to be_created
    
    expect(delete('/folder')).to be_no_content
    expect(get('/folder')).to be_not_found
    expect(get('/folder/a')).to be_not_found
    expect(get('/folder/b')).to be_not_found
  end

  it 'does not allow copy to another domain' do
    expect(put('/test', :input => 'body')).to be_created
    expect(copy('http://localhost/', 'HTTP_DESTINATION' => 'http://another/')).to be_bad_gateway
  end

  it 'does not allow copy to the same resource' do
    expect(put('/test', :input => 'body')).to be_created
    expect(copy('/test', 'HTTP_DESTINATION' => '/test')).to be_forbidden
  end

  it 'copies a single resource' do
    expect(put('/test', :input => 'body')).to be_created
    expect(copy('/test', 'HTTP_DESTINATION' => '/copy')).to be_created
    expect(get('/copy').body).to  eq('body')
  end

  it 'copies a resource with escaped characters' do
    expect(put(url_escape('/a b'), :input => 'body')).to be_created
    expect(copy(url_escape('/a b'), 'HTTP_DESTINATION' => url_escape('/a c'))).to be_created
    expect(get(url_escape('/a c'))).to be_ok
    expect(response.body).to eq('body')
  end
  
  it 'denies a copy without overwrite' do
    expect(put('/test', :input => 'body')).to be_created
    expect(put('/copy', :input => 'copy')).to be_created
    expect(copy('/test', 'HTTP_DESTINATION' => '/copy', 'HTTP_OVERWRITE' => 'F')).to be_precondition_failed
    expect(get('/copy').body).to eq('copy')
  end
  
  it 'allows a copy with overwrite' do
    expect(put('/test', :input => 'body')).to be_created
    expect(put('/copy', :input => 'copy')).to be_created
    expect(copy('/test', 'HTTP_DESTINATION' => '/copy', 'HTTP_OVERWRITE' => 'T')).to be_no_content
    expect(get('/copy').body).to eq('body')
  end
  
  it 'copies a collection' do  
    expect(mkcol('/folder')).to be_created
    copy('/folder', 'HTTP_DESTINATION' => '/copy')
    expect(multi_status_created).to eq true
    propfind('/copy', :input => propfind_xml(:resourcetype))
    expect(multistatus_response('/D:propstat/D:prop/D:resourcetype/D:collection')).not_to be_empty
  end

  it 'copies a collection resursively' do
    expect(mkcol('/folder')).to be_created
    expect(put('/folder/a', :input => 'A')).to be_created
    expect(put('/folder/b', :input => 'B')).to be_created
    
    copy('/folder', 'HTTP_DESTINATION' => '/copy')
    expect(multi_status_created).to eq true
    propfind('/copy', :input => propfind_xml(:resourcetype))
    expect(multistatus_response('/D:propstat/D:prop/D:resourcetype/D:collection')).not_to be_empty
    expect(get('/copy/a').body).to eq('A')
    expect(get('/copy/b').body).to eq('B')
  end
  
  it 'moves a collection recursively' do
    expect(mkcol('/folder')).to be_created
    expect(put('/folder/a', :input => 'A')).to be_created
    expect(put('/folder/b', :input => 'B')).to be_created
    
    move('/folder', 'HTTP_DESTINATION' => '/move')
    expect(multi_status_created).to eq true
    propfind('/move', :input => propfind_xml(:resourcetype))
    expect(multistatus_response('/D:propstat/D:prop/D:resourcetype/D:collection')).not_to be_empty    
    
    expect(get('/move/a').body).to eq('A')
    expect(get('/move/b').body).to eq('B')
    expect(get('/folder/a')).to be_not_found
    expect(get('/folder/b')).to be_not_found
  end
  
  it 'creates a collection' do
    expect(mkcol('/folder')).to be_created
    propfind('/folder', :input => propfind_xml(:resourcetype))
    expect(multistatus_response('/D:propstat/D:prop/D:resourcetype/D:collection')).not_to be_empty
  end
  
  it 'returns full urls after creating a collection' do
    expect(mkcol('/folder')).to be_created
    propfind('/folder', :input => propfind_xml(:resourcetype))
    expect(multistatus_response('/D:propstat/D:prop/D:resourcetype/D:collection')).not_to be_empty
    expect(multistatus_response('/D:href').first.text).to match(/http:\/\/localhost(:\d+)?\/folder/)
  end
  
  it 'does not find properties for nonexistent resources' do
    expect(propfind('/non')).to be_not_found
  end
  
  it 'finds all properties' do
    xml = render(:propfind) do |xml|
      xml.allprop
    end

    propfind('http://localhost/', :input => xml)
    
    expect(multistatus_response('/D:href').first.text.strip).to match(/http:\/\/localhost(:\d+)?\//)

    props = %w(creationdate displayname getlastmodified getetag resourcetype getcontenttype getcontentlength)
    props.each do |prop|
      expect(multistatus_response("/D:propstat/D:prop/D:#{prop}")).not_to be_empty
    end
  end
  
  it 'finds named properties' do
    expect(put('/test.html', :input => '<html/>')).to be_created
    propfind('/test.html', :input => propfind_xml(:getcontenttype, :getcontentlength))

    expect(multistatus_response('/D:propstat/D:prop/D:getcontenttype').first.text).to eq('text/html')
    expect(multistatus_response('/D:propstat/D:prop/D:getcontentlength').first.text).to eq('7')
  end

  it 'locks a resource' do
    expect(put('/test', :input => 'body')).to be_created
    
    xml = render(:lockinfo) do |xml|
      xml.lockscope { xml.exclusive }
      xml.locktype { xml.write }
      xml.owner { xml.href "http://test.de/" }
    end

    lock('/test', :input => xml)
    
    expect(response).to be_ok
    
    result = lambda do |pattern|
      response_xml.xpath "/D:prop/D:lockdiscovery/D:activelock#{pattern}"
    end
    
    expect(result['']).not_to be_empty

    expect(result['/D:locktype']).not_to be_empty
    expect(result['/D:lockscope']).not_to be_empty
    expect(result['/D:depth']).not_to be_empty
    expect(result['/D:timeout']).not_to be_empty
    expect(result['/D:locktoken']).not_to be_empty
    expect(result['/D:owner']).not_to be_empty
  end
  
  context "when mapping a path" do
    before do
      @controller = DAV4Rack::Handler.new(:root => DOC_ROOT, :root_uri_path => '/webdav/')
    end
    
    it "returns correct urls" do
      # FIXME: a put to '/test' works, too -- should it?
      expect(put('/webdav/test', :input => 'body')).to be_created
      expect(response.headers['location']).to match(/http:\/\/localhost(:\d+)?\/webdav\/test/)
    end
  end
end
