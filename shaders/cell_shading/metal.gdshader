shader_type spatial;
render_mode cull_back;

uniform float scale : hint_range(0.1, 10.0) = 1.0;
uniform vec3 metal_color : source_color = vec3(0.7, 0.7, 0.8);
uniform vec3 metal_dark : source_color = vec3(0.3, 0.3, 0.35);
uniform int bands : hint_range(2, 6) = 4;
uniform float specular_strength : hint_range(0.0, 1.0) = 1.0;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.5;
uniform vec4 rim_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

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

void fragment() {
    vec2 uv = UV * scale;
    float scratches = noise(uv * 50.0);
    float dents = noise(uv * 10.0);
    
    vec3 color = mix(metal_dark, metal_color, dents * 0.5 + 0.5);
    color *= 0.95 + scratches * 0.1;
    
    ALBEDO = color;
    METALLIC = 0.9;
    ROUGHNESS = 0.3;
}

void light() {
    float NdotL = dot(NORMAL, LIGHT);
    float light_intensity = smoothstep(0.0, 0.01, NdotL);
    light_intensity = floor(light_intensity * float(bands)) / float(bands);
    
    vec3 diffuse = LIGHT_COLOR * ALBEDO * light_intensity * ATTENUATION;
    
    // Specular muy marcado
    vec3 view_dir = normalize(VIEW);
    vec3 half_vector = normalize(LIGHT + view_dir);
    float NdotH = dot(NORMAL, half_vector);
    float specular_intensity = pow(NdotH * light_intensity, 64.0);
    specular_intensity = smoothstep(0.005, 0.01, specular_intensity);
    vec3 specular = specular_strength * specular_intensity * LIGHT_COLOR * ATTENUATION;
    
    // Rim light
    float rim_dot = 1.0 - dot(view_dir, NORMAL);
    float rim_intensity = rim_dot * pow(NdotL, 0.4);
    rim_intensity = smoothstep(rim_amount - 0.01, rim_amount + 0.01, rim_intensity);
    vec3 rim = rim_intensity * rim_color.rgb;
    
    DIFFUSE_LIGHT += diffuse + specular + rim;
}