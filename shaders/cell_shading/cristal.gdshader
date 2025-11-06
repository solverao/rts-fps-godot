// ===== SHADER 1: CRISTAL / VIDRIO (CELL SHADING) =====
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 crystal_color : source_color = vec3(0.4, 0.7, 1.0);
uniform float refraction_strength : hint_range(0.0, 1.0) = 0.3;
uniform int bands : hint_range(2, 6) = 4;
uniform float transparency : hint_range(0.0, 1.0) = 0.7;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.5;

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
    // Imperfecciones en el cristal
    float imperfections = noise(UV * 20.0) * 0.1;
    
    ALBEDO = crystal_color + vec3(imperfections);
    ALPHA = transparency;
    ROUGHNESS = 0.05;
    METALLIC = 0.0;
}

void light() {
    float NdotL = dot(NORMAL, LIGHT);
    float light_intensity = smoothstep(0.0, 0.01, NdotL);
    light_intensity = floor(light_intensity * float(bands)) / float(bands);
    
    vec3 diffuse = LIGHT_COLOR * ALBEDO * light_intensity * ATTENUATION * 0.5;
    
    // Specular brillante
    vec3 view_dir = normalize(VIEW);
    vec3 half_vector = normalize(LIGHT + view_dir);
    float NdotH = dot(NORMAL, half_vector);
    float specular_intensity = pow(NdotH * light_intensity, 128.0);
    specular_intensity = smoothstep(0.005, 0.01, specular_intensity);
    vec3 specular = specular_intensity * LIGHT_COLOR * ATTENUATION;
    
    // Rim light brillante
    float rim_dot = 1.0 - dot(view_dir, NORMAL);
    float rim_intensity = pow(rim_dot, 3.0);
    rim_intensity = smoothstep(rim_amount - 0.01, rim_amount + 0.01, rim_intensity);
    vec3 rim = rim_intensity * vec3(1.0, 1.0, 1.0) * 0.5;
    
    DIFFUSE_LIGHT += diffuse + specular + rim;
}

/* ===== SHADER 2: MADERA (CELL SHADING) =====
shader_type spatial;
render_mode cull_back;

uniform float scale : hint_range(0.1, 10.0) = 1.0;
uniform vec3 wood_dark : source_color = vec3(0.3, 0.15, 0.05);
uniform vec3 wood_light : source_color = vec3(0.6, 0.4, 0.2);
uniform float ring_frequency : hint_range(1.0, 20.0) = 8.0;
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

void fragment() {
    vec2 uv = UV * scale;
    vec3 pos = VERTEX * scale;
    
    // Anillos de madera
    float dist = length(vec2(pos.x, pos.z));
    float rings = fract(dist * ring_frequency + noise(uv * 2.0) * 0.5);
    rings = smoothstep(0.4, 0.6, rings);
    
    // Variación de color
    float grain = noise(vec2(pos.y * 20.0, dist * 5.0));
    
    vec3 color = mix(wood_dark, wood_light, rings);
    color *= 0.9 + grain * 0.2;
    
    ALBEDO = color;
    ROUGHNESS = 0.6;
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
*/

/* ===== SHADER 3: ENERGÍA / ESCUDO (CELL SHADING ANIMADO) =====
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
*/

/* ===== SHADER 4: NEÓN / CIRCUITOS (CELL SHADING) =====
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
*/

/* ===== SHADER 5: PORTAL / VORTEX (CELL SHADING ANIMADO) =====
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
*/

/* ===== SHADER 6: CAMUFLAJE / CAMOUFLAGE (CELL SHADING) =====
shader_type spatial;
render_mode cull_back;

uniform float scale : hint_range(0.1, 10.0) = 1.0;
uniform vec3 camo_color1 : source_color = vec3(0.2, 0.3, 0.15);
uniform vec3 camo_color2 : source_color = vec3(0.3, 0.4, 0.2);
uniform vec3 camo_color3 : source_color = vec3(0.15, 0.2, 0.1);
uniform vec3 camo_color4 : source_color = vec3(0.4, 0.35, 0.2);
uniform int bands : hint_range(2, 6) = 3;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.716;
uniform vec4 rim_color : source_color = vec4(0.05, 0.1, 0.05, 1.0);

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

vec2 voronoi(vec2 uv) {
    vec2 i_uv = floor(uv);
    vec2 f_uv = fract(uv);
    float min_dist = 1.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 point = vec2(random(i_uv + neighbor), random(i_uv + neighbor + vec2(100.0)));
            vec2 diff = neighbor + point - f_uv;
            float dist = length(diff);
            min_dist = min(min_dist, dist);
        }
    }
    return vec2(min_dist, 0.0);
}

void fragment() {
    vec2 uv = UV * scale;
    
    // Manchas de camuflaje usando Voronoi
    vec2 vor = voronoi(uv * 3.0);
    float pattern = vor.x;
    
    // Agregar variación con ruido
    float n = fbm(uv * 5.0);
    
    // Dividir en 4 regiones de color
    vec3 color;
    if (pattern < 0.25) {
        color = camo_color1;
    } else if (pattern < 0.5) {
        color = camo_color2;
    } else if (pattern < 0.75) {
        color = camo_color3;
    } else {
        color = camo_color4;
    }
    
    // Añadir variación sutil
    color *= 0.9 + n * 0.2;
    
    ALBEDO = color;
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
    vec3 rim = rim_intensity * rim_color.rgb;
    
    DIFFUSE_LIGHT += diffuse + rim;
}
*/