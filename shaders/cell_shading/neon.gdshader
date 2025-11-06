shader_type spatial;
render_mode cull_back;

uniform float scale : hint_range(0.1, 10.0) = 1.0;
uniform vec3 base_color : source_color = vec3(0.05, 0.05, 0.1);
uniform vec3 neon_color : source_color = vec3(0.0, 1.0, 1.0);
uniform float emission_strength : hint_range(0.0, 5.0) = 3.0;
uniform float circuit_density : hint_range(1.0, 20.0) = 8.0;
uniform int bands : hint_range(2, 6) = 3;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.6;

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
    vec2 uv = UV * scale * circuit_density;

    // Crear líneas de circuito
    float lines_h = step(0.95, fract(uv.x));
    float lines_v = step(0.95, fract(uv.y));
    float lines = max(lines_h, lines_v);

    // Puntos de conexión
    vec2 grid = fract(uv);
    float points = step(0.9, max(grid.x, grid.y)) * step(0.9, min(grid.x, grid.y));

    // Variación aleatoria
    float variation = noise(floor(uv)) > 0.7 ? 1.0 : 0.0;

    float circuit_pattern = max(lines, points) * variation;

    // Pulso de energía
    float pulse = sin(TIME * 3.0) * 0.3 + 0.7;

    vec3 color = mix(base_color, neon_color, circuit_pattern);

    ALBEDO = color;
    EMISSION = neon_color * circuit_pattern * emission_strength * pulse;
    ROUGHNESS = 0.8;
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
    vec3 rim = rim_intensity * neon_color * 0.5;

    DIFFUSE_LIGHT += diffuse + rim;
}