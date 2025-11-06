shader_type spatial;
render_mode cull_back;

uniform float scale : hint_range(0.1, 10.0) = 1.0;
uniform vec3 lava_dark : source_color = vec3(0.2, 0.0, 0.0);
uniform vec3 lava_bright : source_color = vec3(1.0, 0.4, 0.0);
uniform vec3 lava_hot : source_color = vec3(1.0, 1.0, 0.3);
uniform float flow_speed : hint_range(0.0, 2.0) = 0.3;
uniform float emission_strength : hint_range(0.0, 5.0) = 2.0;
uniform int bands : hint_range(2, 6) = 3;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.716;
uniform vec4 rim_color : source_color = vec4(0.3, 0.0, 0.0, 1.0);

float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

float noise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a)* u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 st) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amplitude * noise(st);
        st *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    vec2 uv = UV * scale;
    float time_offset = TIME * flow_speed;
    float flow = fbm(uv * 2.0 + vec2(time_offset * 0.5, time_offset));
    float cracks = fbm(uv * 5.0 + vec2(time_offset * 0.2, 0.0));
    cracks = smoothstep(0.3, 0.7, cracks);
    
    vec3 color = mix(lava_dark, lava_bright, flow);
    color = mix(color, lava_hot, cracks);
    
    float pulse = sin(TIME * 2.0) * 0.2 + 0.8;
    color *= pulse;
    
    ALBEDO = color;
    EMISSION = color * emission_strength;
    ROUGHNESS = 0.3;
}

void light() {
    float NdotL = dot(NORMAL, LIGHT);
    float light_intensity = smoothstep(0.0, 0.01, NdotL);
    light_intensity = floor(light_intensity * float(bands)) / float(bands);
    
    vec3 diffuse = LIGHT_COLOR * ALBEDO * light_intensity * ATTENUATION;
    
    vec3 view_dir = normalize(VIEW);
    float rim_dot = 1.0 - dot(view_dir, NORMAL);
    float rim_intensity = rim_dot * pow(NdotL, 0.4);
    rim_intensity = smoothstep(rim_amount - 0.01, rim_amount + 0.01, rim_intensity);
    vec3 rim = rim_intensity * rim_color.rgb;
    
    DIFFUSE_LIGHT += diffuse + rim;
}