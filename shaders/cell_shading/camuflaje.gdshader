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