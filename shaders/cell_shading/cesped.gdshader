/* // ===== SHADER 1: TIERRA / SUELO (CELL SHADING) =====
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
*/

/* ===== SHADER 2: ROCA / PIEDRA (CELL SHADING) =====
shader_type spatial;
render_mode cull_back;

uniform float scale : hint_range(0.1, 10.0) = 1.0;
uniform vec3 rock_dark : source_color = vec3(0.3, 0.3, 0.3);
uniform vec3 rock_light : source_color = vec3(0.6, 0.6, 0.55);
uniform vec3 rock_accent : source_color = vec3(0.4, 0.35, 0.3);
uniform int bands : hint_range(2, 6) = 3;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.716;
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

float fbm(vec2 st) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 6; i++) {
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
    float n = fbm(uv * 2.0);
    vec2 vor = voronoi(uv * 5.0);
    float cracks = smoothstep(0.0, 0.1, vor.x);
    
    vec3 base = mix(rock_dark, rock_light, n);
    base = mix(base, rock_accent, noise(uv * 8.0) * 0.3);
    base = mix(rock_dark * 0.5, base, cracks);
    
    ALBEDO = base;
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

 //===== SHADER 3: CÉSPED / HIERBA (CELL SHADING) =====
shader_type spatial;
render_mode cull_back;

uniform float scale : hint_range(0.1, 10.0) = 1.0;
uniform vec3 grass_dark : source_color = vec3(0.2, 0.4, 0.1);
uniform vec3 grass_light : source_color = vec3(0.4, 0.7, 0.2);
uniform vec3 grass_yellow : source_color = vec3(0.6, 0.7, 0.3);
uniform int bands : hint_range(2, 6) = 3;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.716;
uniform vec4 rim_color : source_color = vec4(0.05, 0.1, 0.0, 1.0);

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
    float n = fbm(uv * 5.0);
    float blades = noise(vec2(uv.x * 50.0, uv.y * 10.0));
    blades = smoothstep(0.4, 0.6, blades);
    
    vec3 base = mix(grass_dark, grass_light, n);
    base = mix(base, grass_yellow, blades * 0.3);
    float patches = fbm(uv * 2.0);
    base *= 0.8 + patches * 0.4;
    
    ALBEDO = base;
    ROUGHNESS = 0.7;
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


/* ===== SHADER 4: AGUA (CELL SHADING) =====
shader_type spatial;
render_mode cull_back;

uniform float scale : hint_range(0.1, 10.0) = 1.0;
uniform vec3 water_deep : source_color = vec3(0.0, 0.2, 0.4);
uniform vec3 water_shallow : source_color = vec3(0.2, 0.5, 0.7);
uniform float wave_speed : hint_range(0.0, 2.0) = 0.5;
uniform int bands : hint_range(2, 6) = 4;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.8;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.5;
uniform vec4 rim_color : source_color = vec4(0.0, 0.1, 0.2, 1.0);

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
    float time_offset = TIME * wave_speed;
    float wave1 = noise(uv * 3.0 + vec2(time_offset, 0.0));
    float wave2 = noise(uv * 5.0 - vec2(0.0, time_offset * 0.7));
    float waves = (wave1 + wave2) * 0.5;
    
    vec3 color = mix(water_deep, water_shallow, waves);
    
    ALBEDO = color;
    ROUGHNESS = 0.1;
}

void light() {
    float NdotL = dot(NORMAL, LIGHT);
    float light_intensity = smoothstep(0.0, 0.01, NdotL);
    light_intensity = floor(light_intensity * float(bands)) / float(bands);
    
    vec3 diffuse = LIGHT_COLOR * ALBEDO * light_intensity * ATTENUATION;
    
    // Specular cel-shaded
    vec3 view_dir = normalize(VIEW);
    vec3 half_vector = normalize(LIGHT + view_dir);
    float NdotH = dot(NORMAL, half_vector);
    float specular_intensity = pow(NdotH * light_intensity, 32.0);
    specular_intensity = smoothstep(0.005, 0.01, specular_intensity);
    vec3 specular = specular_strength * specular_intensity * LIGHT_COLOR * ATTENUATION;
    
    // Rim light
    float rim_dot = 1.0 - dot(view_dir, NORMAL);
    float rim_intensity = rim_dot * pow(NdotL, 0.4);
    rim_intensity = smoothstep(rim_amount - 0.01, rim_amount + 0.01, rim_intensity);
    vec3 rim = rim_intensity * rim_color.rgb;
    
    DIFFUSE_LIGHT += diffuse + specular + rim;
}
*/

/* ===== SHADER 5: LAVA (CELL SHADING + EMISIÓN) =====
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
*/

/* ===== SHADER 6: METAL (CELL SHADING) =====
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
*/