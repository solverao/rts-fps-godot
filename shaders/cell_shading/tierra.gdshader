// ===== SHADER 1: TIERRA / SUELO (CELL SHADING) =====
shader_type spatial;
render_mode cull_back;

uniform float scale : hint_range(0.1, 10.0) = 1.0;
uniform vec3 dirt_dark : source_color = vec3(0.3, 0.2, 0.1);
uniform vec3 dirt_light : source_color = vec3(0.5, 0.35, 0.2);
uniform int bands : hint_range(2, 6) = 3;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.716;
uniform vec4 rim_color : source_color = vec4(0.1, 0.05, 0.0, 1.0);

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
    vec3 pos = VERTEX * scale;
    
    float n = fbm(uv * 3.0);
    float n2 = fbm(vec2(pos.x + pos.z, pos.y) * 2.0);
    float combined = mix(n, n2, 0.5);
    
    vec3 color = mix(dirt_dark, dirt_light, combined);
    float detail = noise(uv * 20.0) * 0.1;
    color += detail;
    
    ALBEDO = color;
    ROUGHNESS = 0.9;
}

void light() {
    // Cell shading
    float NdotL = dot(NORMAL, LIGHT);
    float light_intensity = smoothstep(0.0, 0.01, NdotL);
    light_intensity = floor(light_intensity * float(bands)) / float(bands);
    
    vec3 diffuse = LIGHT_COLOR * ALBEDO * light_intensity * ATTENUATION;
    
    // Rim light (simula contorno)
    vec3 view_dir = normalize(VIEW);
    float rim_dot = 1.0 - dot(view_dir, NORMAL);
    float rim_intensity = rim_dot * pow(NdotL, 0.4);
    rim_intensity = smoothstep(rim_amount - 0.01, rim_amount + 0.01, rim_intensity);
    vec3 rim = rim_intensity * rim_color.rgb;
    
    DIFFUSE_LIGHT += diffuse + rim;
}