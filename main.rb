Shoes.app(title: "Eventbrite Data Pull", width: 600, height: 370) do
  background white
  stack margin: 10 do

    stack margin: 10 do
      background darkorange
      subtitle "Eventbrite", font: "lacuna"
    end
  end

  stack margin: 10 do
    @list_title = para " Enter one or two dates (yyyy-mm-dd) or a list of EIDs. Separate all items with commas"
    @list = edit_line

    flow do
      para "Push to Salesforce?"
      @salesforce = check
    end

    flow do
      @event_radio = radio :scrape_choice
      para "Event EIDs"
    end

    flow do
      @date_radio = radio :scrape_choice
      para "Dates (yyyy-mm-dd)"
    end

  button "Scrape!" do
    if @event_radio.checked?
      @arg = "#{@list.text}"
      if @salesforce.checked?
        `ruby EventbriteScrape.rb -e #{@arg} -S`
      else
        `ruby EventbriteScrape.rb -e #{@arg}`
      end
    else
      @arg = "#{@list.text}"
      if @salesforce.checked?
        `ruby EventbriteScrape.rb -d #{@arg} -S`
      else
        `ruby EventbriteScrape.rb -d #{@arg}`
      end
    end
  end

  end
end
