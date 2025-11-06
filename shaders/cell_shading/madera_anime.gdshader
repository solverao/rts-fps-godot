shader_type spatial;
render_mode cull_back;

// Colores de la madera
uniform vec3 wood_dark : source_color = vec3(0.4, 0.25, 0.15);
uniform vec3 wood_base : source_color = vec3(0.6, 0.4, 0.25);
uniform vec3 wood_light : source_color = vec3(0.8, 0.6, 0.4);
uniform vec3 wood_highlight : source_color = vec3(0.9, 0.75, 0.55);

// Parámetros de la textura
uniform float scale : hint_range(0.1, 10.0) = 1.0;
uniform float ring_frequency : hint_range(1.0, 30.0) = 12.0;
uniform float grain_intensity : hint_range(0.0, 1.0) = 0.4;

// Cell Shading
uniform int shadow_bands : hint_range(2, 5) = 3;
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.5;

// Contorno tipo anime
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.8;
uniform float rim_width : hint_range(0.0, 0.5) = 0.1;
uniform vec4 rim_color : source_color = vec4(0.2, 0.1, 0.05, 1.0);

// Brillo estilo anime
uniform float specular_threshold : hint_range(0.0, 1.0) = 0.9;
uniform float specular_smoothness : hint_range(0.0, 0.1) = 0.02;
uniform vec3 specular_color : source_color = vec3(1.0, 0.95, 0.8);
uniform float specular_strength : hint_range(0.0, 2.0) = 0.8;

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
    for (int i = 0; i < 3; i++) {
        value += amplitude * noise(st);
        st *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    vec3 pos = VERTEX * scale;
    vec2 uv = UV * scale;
    
    // Crear anillos de madera (en el plano XZ)
    float dist = length(vec2(pos.x, pos.z));
    
    // Distorsión orgánica de los anillos
    float distortion = fbm(vec2(pos.x, pos.z) * 2.0) * 0.3;
    dist += distortion;
    
    // Anillos con transiciones suaves
    float rings = fract(dist * ring_frequency);
    
    // Crear 3 bandas de color para look anime
    vec3 color;
    if (rings < 0.3) {
        color = wood_dark;
    } else if (rings < 0.6) {
        color = wood_base;
    } else {
        color = wood_light;
    }
    
    // Vetas de madera (en dirección Y)
    float grain = fbm(vec2(pos.y * 20.0, dist * 3.0));
    grain = smoothstep(0.4, 0.6, grain);
    
    // Aplicar vetas de forma sutil
    color = mix(color, color * 0.85, grain * grain_intensity);
    
    // Añadir variación de brillo tipo anime
    float highlight_noise = noise(uv * 8.0);
    if (highlight_noise > 0.8) {
        color = mix(color, wood_highlight, 0.3);
    }
    
    ALBEDO = color;
    ROUGHNESS = 0.6;
}

void light() {
    float NdotL = dot(NORMAL, LIGHT);
    
    // === SOMBRAS ESTILO ANIME (bandas discretas) ===
    float light_intensity = smoothstep(shadow_threshold - 0.01, shadow_threshold + 0.01, NdotL);
    
    // Crear bandas bien definidas
    light_intensity = floor(light_intensity * float(shadow_bands)) / float(shadow_bands);
    
    // Asegurar que hay al menos un poco de luz ambiente
    light_intensity = max(light_intensity, 0.3);
    
    vec3 diffuse = LIGHT_COLOR * ALBEDO * light_intensity * ATTENUATION;
    
    // === BRILLO ESPECULAR ESTILO ANIME (puntual y brillante) ===
    vec3 view_dir = normalize(VIEW);
    vec3 half_vector = normalize(LIGHT + view_dir);
    float NdotH = dot(NORMAL, half_vector);
    
    // Brillo súper definido tipo anime
    float specular_intensity = smoothstep(
        specular_threshold - specular_smoothness,
        specular_threshold + specular_smoothness,
        NdotH
    );
    
    // Solo mostrar brillo en áreas iluminadas
    specular_intensity *= step(0.0, NdotL);
    
    vec3 specular = specular_color * specular_intensity * specular_strength * ATTENUATION;
    
    // === RIM LIGHT (contorno luminoso tipo anime) ===
    float rim_dot = 1.0 - dot(view_dir, NORMAL);
    
    // Rim light bien definido
    float rim_intensity = smoothstep(
        rim_threshold - rim_width,
        rim_threshold,
        rim_dot
    );
    
    // Solo en áreas iluminadas
    rim_intensity *= smoothstep(0.0, 0.2, NdotL);
    
    vec3 rim = rim_color.rgb * rim_intensity;
    
    // Combinar todo
    DIFFUSE_LIGHT += diffuse + specular + rim;
}