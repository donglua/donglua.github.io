require 'nokogiri'

Jekyll::Hooks.register [:posts, :pages], :post_render do |doc|
  # Only process HTML documents
  if doc.output_ext == '.html'
    content = doc.output

    # Optimization: Skip Nokogiri parsing if no mermaid blocks are present
    next if content.nil? || !content.include?('language-mermaid')

    # Using Nokogiri to parse the HTML
    fragment = Nokogiri::HTML::DocumentFragment.parse(content)

    # Find all <pre><code class="language-mermaid"> elements
    mermaid_blocks = fragment.css('pre > code.language-mermaid')

    if mermaid_blocks.any?
      mermaid_blocks.each do |code_element|
        pre_element = code_element.parent

        # Create the new div
        mermaid_div = Nokogiri::XML::Node.new('div', fragment)
        mermaid_div['class'] = 'mermaid'
        mermaid_div.content = code_element.content

        # Replace the pre element with the new div
        pre_element.replace(mermaid_div)
      end

      # Update the document output
      doc.output = fragment.to_html
    end
  end
end
