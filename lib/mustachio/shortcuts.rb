require 'face'

Magickly.dragonfly.configure do |c|
  c.log_commands = true
  
  c.analyser.add :face_data do |temp_object|
    Mustachio.face_data(temp_object)
  end
  
  c.analyser.add :face_data_as_px do |temp_object|
    Mustachio.face_data_as_px(temp_object)
  end
  
  c.analyser.add :face_span do |temp_object|
    Mustachio.face_span(temp_object)
  end
  
  
  
  c.job :mustachify do |stache_name_param|
    photo_data = Mustachio.face_data_as_px(@job)
    width = photo_data['width']
    height = photo_data['height']
    
    commands = ['-virtual-pixel transparent']
    photo_data['tags'].each do |face|
      stache_name = case stache_name_param
        when true
          'hipster'
        when 'true'
          'hipster'
        when 'rand'
          Mustachio.mustaches.keys[rand(Mustachio.mustaches.size)]
        else
          stache_name_param
      end
      
      mustache = Mustachio.mustaches[stache_name]
      
      # perform transform such that the mustache is the height
      # of the upper lip, and the bottom-center of the stache
      # is mapped to the center of the mouth
      rotation = Math.atan(
        ( face['eye_right']['y'] - face['eye_left']['y'] ).to_f /
        ( face['eye_right']['x'] - face['eye_left']['x'] ).to_f
      ) / Math::PI * 180.0

      case mustache['placement']
      when 'lip'
        desired_height = Math.sqrt(
          ( face['nose']['x'] - face['mouth_center']['x'] ).to_f**2 +
          ( face['nose']['y'] - face['mouth_center']['y'] ).to_f**2
        )
        mouth_intersect = mustache['height'] - mustache['mouth_overlap']
        scale = desired_height / mouth_intersect
        
        srt_params = [
          [ mustache['width'] / 2.0, mouth_intersect - mustache['vert_offset'] ].map{|e| e.to_i }.join(','), # bottom-center of stache
          scale, # scale
          rotation, # rotate
          [ face['mouth_center']['x'], face['mouth_center']['y'] ].map{|e| e.to_i }.join(',') # middle of mouth
        ]
      when 'head'
        desired_height = height * (face['height'] / 100)
        head_intersect = mustache['height'] / 2
        scale = desired_height / head_intersect

        srt_params = [
          [ mustache['width'] / 2, mustache['height'] / 2 ].map{|e| e.to_i }.join(','), # middle of image
          scale,
          rotation, # rotate
          [ face['center']['x'], face['center']['y'] - mustache['vert_offset'] ].map{|e| e.to_i }.join(',') # middle of head
        ]
      when 'eyes'
        desired_width = width * (face['width'] / 100)
        eye_intersect = mustache['width'] / 1.1
        scale = desired_width / eye_intersect

        srt_params = [
          [ mustache['width'] / 2, mustache['height'] / 2 ].map{|e| e.to_i }.join(','), # middle of eyes
          scale,
          rotation, # rotate
          [
            (face['eye_left']['x'] + face['eye_right']['x'] ).to_f / 2,
            ((face['eye_left']['y'] + face['eye_right']['y'] ).to_f / 2) - mustache['vert_offset'].to_i 
          ].map{|e| e.to_i }.join(',') # middle of eyes
        ]
      end

      srt_params_str = srt_params.join(' ')
      
      commands << "\\( #{mustache['file_path']} +distort SRT '#{srt_params_str}' \\)"
    end
    commands << "-flatten"
    
    command_str = commands.join(' ')
    process :convert, command_str
  end
  
  c.job :crop_to_faces do |geometry|
    thumb_width, thumb_height = geometry.split('x')
    # raise ArgumentError
    thumb_width = thumb_width.to_f
    thumb_height = thumb_height.to_f
    
    span = Mustachio.face_span(@job)
    puts span.inspect
    scale_x = thumb_width / span[:width]
    scale_y = thumb_height / span[:height]
    
    # TODO
    # if thumb larger than span
    # center span and crop
    # else
    # resize image so span is smaller than thumb, then crop
    
    # center the span in the dimension with the smaller scale
    if scale_x < scale_y
      orig_height = @job.height
      # check if image is tall enough for this scaling
      if orig_height * scale_x >= thumb_height
        @scale = scale_x
        @offset_x = span[:left] * @scale
      else
        # image is too short - increase scale to fit height
        @scale = thumb_height / orig_height.to_f
        orig_width = @job.width
        @offset_x = span[:left] * @scale + ((@scale - scale_x) * orig_width / 2.0)
      end
      
      @offset_y = (span[:center_y] * @scale) - (thumb_height / 2)
    else
      orig_width = @job.width
      # check if image is wide enough for this scaling
      if orig_width * scale_y >= thumb_width
        @scale = scale_y
        @offset_y = span[:top] * @scale
      else
        # image is too narrow - increase scale to fit width
        @scale = thumb_width / orig_width.to_f
        orig_height = @job.height
        @offset_y = span[:top] * @scale + ((@scale - scale_y) * orig_height / 2.0)
      end
      
      @offset_x = (span[:center_x] * @scale) - (thumb_width / 2)
    end
    
    # round up, to ensure the scaled image fills the thumb area
    percentage = (@scale * 100).ceil
    
    process :convert, "-resize #{percentage}% -extent #{geometry}+#{@offset_x.to_i}+#{@offset_y.to_i}"
  end
end