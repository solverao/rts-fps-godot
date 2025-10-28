shader_type spatial;
render_mode cull_back;

// Colores del césped
uniform vec3 grass_shadow : source_color = vec3(0.15, 0.3, 0.1);
uniform vec3 grass_base : source_color = vec3(0.3, 0.55, 0.2);
uniform vec3 grass_light : source_color = vec3(0.5, 0.75, 0.3);
uniform vec3 grass_bright : source_color = vec3(0.7, 0.9, 0.5);

// Detalles del césped
uniform float scale : hint_range(0.1, 10.0) = 1.0;
uniform float blade_frequency : hint_range(10.0, 100.0) = 40.0;
uniform float variation_amount : hint_range(0.0, 1.0) = 0.5;
uniform float wind_speed : hint_range(0.0, 2.0) = 0.5;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.3;

// Cell Shading
uniform int shadow_bands : hint_range(2, 5) = 3;
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.5;

// Contorno tipo anime
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.75;
uniform float rim_width : hint_range(0.0, 0.5) = 0.15;
uniform vec4 rim_color : source_color = vec4(0.1, 0.2, 0.05, 1.0);

// Brillo estilo anime (rocío/humedad)
uniform float specular_threshold : hint_range(0.0, 1.0) = 0.95;
uniform float specular_smoothness : hint_range(0.0, 0.1) = 0.01;
uniform vec3 specular_color : source_color = vec3(1.0, 1.0, 0.9);
uniform float specular_strength : hint_range(0.0, 2.0) = 1.2;

// Manchas de césped (estilo anime)
uniform float patch_size : hint_range(0.1, 5.0) = 1.5;
uniform float patch_contrast : hint_range(0.0, 1.0) = 0.4;

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
    vec3 pos = VERTEX * scale;
    
    // === PATRÓN DE BRIZNAS DE HIERBA ===
    // Patrón vertical (briznas)
    float blades = sin(uv.x * blade_frequency + noise(uv * 5.0) * 3.0);
    blades = blades * 0.5 + 0.5;
    
    // Añadir textura horizontal
    float horizontal = noise(vec2(uv.x * blade_frequency * 0.5, uv.y * blade_frequency * 2.0));
    blades = mix(blades, horizontal, 0.3);
    
    // === MANCHAS DE CÉSPED (ESTILO ANIME) ===
    float patches = fbm(uv * patch_size);
    patches = smoothstep(0.3, 0.7, patches);
    
    // === VIENTO ANIMADO ===
    float wind = sin(uv.x * 5.0 + TIME * wind_speed) * cos(uv.y * 3.0 + TIME * wind_speed * 0.7);
    wind = wind * wind_strength;
    
    // Aplicar viento a las briznas
    blades += wind * 0.2;
    
    // === SELECCIÓN DE COLOR BASE (3 BANDAS ANIME) ===
    vec3 color;
    float combined = blades * 0.6 + patches * 0.4;
    
    if (combined < 0.33) {
        color = grass_shadow;
    } else if (combined < 0.66) {
        color = grass_base;
    } else {
        color = grass_light;
    }
    
    // === VARIACIÓN DE COLOR ===
    float variation = noise(uv * 15.0);
    if (variation > 0.85) {
        // Pequeñas áreas más brillantes (flores o césped nuevo)
        color = mix(color, grass_bright, 0.5);
    } else if (variation < 0.15) {
        // Pequeñas áreas más oscuras (sombra o tierra)
        color = mix(color, grass_shadow, 0.3);
    }
    
    // === MANCHAS DE CONTRASTE (ESTILO ANIME) ===
    float dark_patches = smoothstep(0.7, 0.8, fbm(uv * patch_size * 0.5));
    color = mix(color, grass_shadow, dark_patches * patch_contrast);
    
    ALBEDO = color;
    ROUGHNESS = 0.7;
}

void light() {
    float NdotL = dot(NORMAL, LIGHT);
    
    // === SOMBRAS ESTILO ANIME (bandas discretas) ===
    float light_intensity = smoothstep(shadow_threshold - 0.01, shadow_threshold + 0.01, NdotL);
    
    // Crear bandas bien definidas
    light_intensity = floor(light_intensity * float(shadow_bands)) / float(shadow_bands);
    
    // Luz ambiente mínima
    light_intensity = max(light_intensity, 0.35);
    
    vec3 diffuse = LIGHT_COLOR * ALBEDO * light_intensity * ATTENUATION;
    
    // === BRILLO ESPECULAR (ROCÍO/HUMEDAD ESTILO ANIME) ===
    vec3 view_dir = normalize(VIEW);
    vec3 half_vector = normalize(LIGHT + view_dir);
    float NdotH = dot(NORMAL, half_vector);
    
    // Brillos pequeños y puntuales tipo anime
    float specular_intensity = smoothstep(
        specular_threshold - specular_smoothness,
        specular_threshold + specular_smoothness,
        NdotH
    );
    
    // Solo en áreas iluminadas
    specular_intensity *= step(0.0, NdotL);
    
    // Hacer que los brillos sean más dispersos
    float specular_noise = noise(UV * 50.0);
    specular_intensity *= step(0.7, specular_noise);
    
    vec3 specular = specular_color * specular_intensity * specular_strength * ATTENUATION;
    
    // === RIM LIGHT (contorno luminoso tipo anime) ===
    float rim_dot = 1.0 - dot(view_dir, NORMAL);
    
    // Rim light definido
    float rim_intensity = smoothstep(
        rim_threshold - rim_width,
        rim_threshold,
        rim_dot
    );
    
    // Solo en áreas con luz
    rim_intensity *= smoothstep(0.0, 0.3, NdotL);
    
    vec3 rim = rim_color.rgb * rim_intensity;
    
    // === DETALLE EXTRA: Subsurface scattering simple ===
    // El césped es translúcido, deja pasar algo de luz
    float back_light = max(0.0, -NdotL);
    vec3 subsurface = ALBEDO * back_light * 0.3 * LIGHT_COLOR * ATTENUATION;
    
    // Combinar todo
    DIFFUSE_LIGHT += diffuse + specular + rim + subsurface;
}
