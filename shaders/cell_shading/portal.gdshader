shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_back;

uniform vec3 portal_color1 : source_color = vec3(0.5, 0.0, 1.0);
uniform vec3 portal_color2 : source_color = vec3(0.0, 0.5, 1.0);
uniform float rotation_speed : hint_range(0.0, 5.0) = 1.0;
uniform float swirl_intensity : hint_range(0.0, 5.0) = 2.0;
uniform float emission_power : hint_range(0.0, 10.0) = 5.0;

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
    vec2 uv = UV - 0.5;
    float dist = length(uv);
    float angle = atan(uv.y, uv.x);
    
    // Rotación y espiral
    float time = TIME * rotation_speed;
    float spiral = angle + dist * swirl_intensity - time;
    
    // Anillos animados
    float rings = fract(dist * 10.0 - time * 2.0);
    rings = smoothstep(0.3, 0.7, rings);
    
    // Patrón de espiral
    float spiral_pattern = sin(spiral * 8.0) * 0.5 + 0.5;
    
    // Combinar patrones
    float combined = rings * spiral_pattern;
    
    // Mezclar colores
    vec3 color = mix(portal_color1, portal_color2, combined);
    
    // Más brillante en el centro
    float center_glow = 1.0 - smoothstep(0.0, 0.5, dist);
    
    ALBEDO = color;
    EMISSION = color * emission_power * (combined * 0.5 + center_glow * 0.5);
    ALPHA = combined * 0.8 + 0.2;
}