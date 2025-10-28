shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_back, unshaded;

uniform vec3 energy_color : source_color = vec3(0.0, 0.8, 1.0);
uniform vec3 energy_color2 : source_color = vec3(0.0, 1.0, 0.5);
uniform float speed : hint_range(0.0, 5.0) = 1.0;
uniform float scale : hint_range(0.1, 10.0) = 2.0;
uniform float power : hint_range(0.0, 5.0) = 2.0;

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
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(st);
        st *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    vec2 uv = UV * scale;
    float time = TIME * speed;
    
    // Patrón de energía animado
    float pattern1 = fbm(uv + vec2(time, 0.0));
    float pattern2 = fbm(uv - vec2(0.0, time * 0.7));
    float combined = (pattern1 + pattern2) * 0.5;
    
    // Líneas de energía
    float lines = sin(uv.y * 20.0 + time * 5.0) * 0.5 + 0.5;
    lines = smoothstep(0.4, 0.6, lines);
    
    // Mezclar colores
    vec3 color = mix(energy_color, energy_color2, combined);
    color *= lines * 0.5 + 0.5;
    
    // Pulso
    float pulse = sin(time * 3.0) * 0.3 + 0.7;
    
    // Fresnel efecto (brillo en bordes)
    vec3 view_dir = normalize(VIEW);
    float fresnel = 1.0 - dot(view_dir, NORMAL);
    fresnel = pow(fresnel, 3.0);
    
    ALBEDO = color * pulse;
    EMISSION = color * power * fresnel;
    ALPHA = fresnel * 0.8;
}