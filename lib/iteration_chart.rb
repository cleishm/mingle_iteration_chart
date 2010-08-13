class IterationChart
  
  @@types = {
    'points' => :points,
    'line' => :line,
    'area' => :area,
    'bar' => :bar
  }

  def initialize(parameters, project, current_user)
    @parameters = parameters
    @project = project
    @current_user = current_user
    
    @parameters['iteration-card-type'].nil? and raise "Requires parameter iteration-card-type"
    @parameters['series'].nil? and raise "Requires parameter series"
  end
    
  def execute
    tag_id = (0...8).map{65.+(rand(25)).chr}.join
    
    @iterations = @project.execute_mql('select number, name where type = "' + @parameters['iteration-card-type'] + '" order by number')
    
    series = @parameters['series'].reverse.inject([]){|series, definition|
      aseries = yaml_definition_to_series(definition)
      points = points_for_a_series(aseries)
      last_stacked = series.find{|s| s[:stack]}
      aseries[:points] = (!aseries[:stack] || last_stacked.nil?) ? points : sum_points(last_stacked[:points], points)
      series.unshift(aseries)
    }
    
    iterations_from = iteration_description_to_i(@parameters['iterations-from'])
    iterations_to = iteration_description_to_i(@parameters['iterations-to'])
     
    min_y = to_f_or_nil(@parameters['min'])
    max_y = to_f_or_nil(@parameters['max'])
    
    fill = (@parameters['transparent-fills'] != false)? 'true' : '1'
    show_legend = @parameters['legend'] != false
    legend_columns = to_i_or_nil(@parameters['legend'])

  <<-HTML
    <script language="javascript" type="text/javascript" src="../../../../plugin_assets/iteration_chart/javascripts/excanvas.compiled.js"></script>
    <script language="javascript" type="text/javascript" src="../../../../plugin_assets/iteration_chart/javascripts/jquery.min.js"></script>
    <script language="javascript" type="text/javascript" src="../../../../plugin_assets/iteration_chart/javascripts/jquery.flot.min.js"></script>
    <div id="iterchart#{tag_id}" style="width:600px;height:300px;"></div>
    #{show_legend ? "<div id='iterchartlegend#{tag_id}' style='width:600px;margin:0 auto;padding:10px'></div>" : ""}
    
    <script id="source" language="javascript" type="text/javascript">
    jQuery.noConflict();
    (function($) {
      $(function () {
        xlabels = [#{@iterations.collect{|iteration| '"' + iteration['name'] + '"'}.join(',')}];
        $.plot($('#iterchart#{tag_id}'), [
        #{series.collect{|aseries|
          '{' +
            [(aseries[:label].nil? ? nil : 'label:' + quote_if_string(aseries[:label]).to_s),
             (aseries[:color].nil? ? nil : 'color:' + quote_if_string(aseries[:color]).to_s),
             aseries[:types].collect{|type|
               case type
               when :points then "points:{show:true}"
               when :line then "lines:{show:true}"
               when :area then "lines:{show:true,fill:#{fill},lineWidth:1}"
               when :bar then "bars:{show:true,barWidth:1,align:'center',fill:#{fill}}"
               end
             },
             'data:[' + aseries[:points].collect{|point| '[' + point.join(',') + ']' }.join(',') + ']'
            ].flatten.compact.join(',') +
          '}'
        }.join(',')}
        ], {
          legend: {
            show: #{show_legend.to_s},
            container: '#iterchartlegend#{tag_id}',
            noColumns: #{legend_columns.nil? ? 'undefined' : legend_columns}
          },
          xaxis: {
            minTickSize: 1,
            min: #{iterations_from.nil? ? 'undefined' : iterations_from},
            max: #{iterations_to.nil? ? 'undefined' : iterations_to},
            tickFormatter: function(val, axis) {
              return (val == axis.min || xlabels[val] == undefined)? "" : xlabels[val];
            }
          },
          yaxis: {
            min: #{min_y.nil? ? 'undefined' : min_y},
            max: #{max_y.nil? ? 'undefined' : max_y}
          },
          grid: {
            markings: function (axes) {
              var markings = [];
              for (var x = Math.floor(axes.xaxis.min); x < axes.xaxis.max; x += 1) {
                markings.push({ xaxis:{ from:x, to:x, lineWidth:1, color:"#000000"}});
              }
              markings.push({ yaxis:{ from:0, to:0 }, lineWidth:2, color:"#000000" });
              return markings;
            }
          }
        });
      });
    })(jQuery);
    </script>
  HTML
  
  end
  
  def yaml_definition_to_series(definition)
    data = definition['data'] || []
    data = data.is_a?(Array) ? data : [{ 'query' => data }]
    {
      :label => definition['label'],
      :color => definition['color'],
      :types => types_description_to_types(definition['type']),
      :cumulative => (definition['cumulative'] == true),
      :stack => (definition['stack'] == true || (@parameters['stacked'] == true && definition['stack'] != false)),
      :negate => (definition['negate'] == true),
      :offset => definition['offset'].to_f,
      :iterations_from => iteration_description_to_i(definition['iterations-from']),
      :iterations_to => iteration_description_to_i(definition['iterations-to']),
      :queries => data.collect{|query|
        {
          :query => query['query'],
          :cumulative => (query['cumulative'] == true),
          :negate => (query['negate'] == true),
          :offset => query['offset'].to_f,
          :iterations_from => iteration_description_to_i(query['iterations-from']),
          :iterations_to => iteration_description_to_i(query['iterations-to'])
        }
      }
    }
  end
  
  def iteration_description_to_i(iteration)
    case iteration
    when nil then nil
    when 'first' then 0
    when 'last' then @iterations.length
    else to_i_or_nil(iteration)
    end
  end
  
  def types_description_to_types(description)
    types = description.split(',').collect{|type| @@types[type.strip]}
    types.include?(:area) and types.delete(:line)
    types.empty? ? [:points] : types
  end
  
  def points_for_a_series(aseries)
    points = post_process_points(sum_points(*aseries[:queries].collect{|query|
      post_process_points(
        mql_results_to_points(@project.execute_mql(query[:query])),
        query);
    }), aseries)
    points = points.select{|point| point[1] != 0} if aseries[:types].include?(:bar)
    points
  end
  
  def mql_results_to_points(mql_result)
    mql_result.collect{|row|
      [iteration_index(row.values.first), row.values.second.to_f]
    }.select{|point| point[1] != 0}
  end
  
  def post_process_points(points, options)
    points = select_points_between_iterations(points, options[:iterations_from], options[:iterations_to])
    options[:negate] and points = points.collect{|point| [point[0], -1 * point[1]]}
    points = pad_points(points, options[:iteration_from])
    options[:cumulative] and points = cumulate_points(points)
    options[:offset] != 0 and points = offset_points(points, options[:offset])
    points
  end
  
  def sum_points(*points)
    (points.inject{|x,y| x.clone.concat(y)}||[]).sort {|x,y| x.first <=> y.first }.inject([]) {|summed, point|
      prev = (summed.last||[nil,0])
      prev[0] == point[0] ? summed.slice(0..-2).push([point[0], prev[1] + point[1]]) : summed.push(point)
    }
  end
  
  def cumulate_points(points)
    points.inject([]) {|cumulative, point|
      prev = cumulative.last
      prev.nil? ? [point] : cumulative.push([point[0], prev[1] + point[1]])
    }
  end
  
  def offset_points(points, offset)
    points.collect{|point| [point[0] + offset, point[1]] }
  end
  
  def pad_points(points, from = nil)
    points.inject([]) {|result, point|
      prev = (result.last || [(from||0)-1,nil])
      result.concat((prev[0]+1..point[0]-1).collect{|offset| [offset,0]}).push(point)
    }
  end
  
  def select_points_between_iterations(points, from, to)
    points.select{|point|
      (from.nil? || point[0] >= from) && (to.nil? || point[0] <= to)
    }
  end
  
  def iteration_index(iteration_display_value)
    number = iteration_display_value.slice(/^#(\d+) /, 1)
    raise "Unknown iteration: " + iteration_display_value if number.nil?
    @iterations.index(@iterations.find{|iteration| iteration['number'] == number})
  end
  
  def to_i_or_nil(obj)
    string = obj.to_s
    (string.nil? || string.match(/^[-+]?\d+$/) == nil) ? nil : string.to_i
  end
  
  def to_f_or_nil(obj)
    string = obj.to_s
    (string.nil? || string.match(/^[-+]?\d+\.?\d*$/) == nil) ? nil : string.to_f
  end
  
  def quote_if_string(obj)
    [Numeric, TrueClass, FalseClass].any?{|type| obj.is_a?(type)} ? obj : '"' + obj.to_s + '"'
  end
 
  def can_be_cached?
    true  # if appropriate, switch to true once you move your macro to production
  end
    
end

