// Define el tipo de shader como 'spatial' (para 3D)
shader_type spatial;

// --- Variables (Uniforms) ---
// Aparecerán en el Inspector para que las ajustes.

// Texturas
uniform sampler2D texture_rock : source_color;
uniform sampler2D texture_moss : source_color;

// Escala de las texturas (qué tan grandes o pequeñas se ven)
uniform float scale : hint_range(0.1, 10.0) = 1.0;

// Dónde empieza la mezcla (0.0 = ecuador, 1.0 = polo norte)
uniform float blend_offset : hint_range(-1.0, 1.0) = 0.5;
// Qué tan nítida es la transición entre roca y musgo
uniform float blend_sharpness : hint_range(0.01, 1.0) = 0.1;


// --- Función de Mapeo Triplanar ---
// Una función reutilizable para proyectar una textura desde X, Y, Z
vec3 triplanar_texture(sampler2D tex, vec3 world_pos, vec3 world_normal) {
    
    // 1. Calcular los pesos (weights)
    // Qué tanta influencia tiene cada eje (X, Y, Z)
    vec3 weights = abs(world_normal);
    // Normalizar los pesos para que sumen 1.0
    weights /= (weights.x + weights.y + weights.z);

    // 2. Muestrear (leer) las texturas desde cada eje
    // Usamos la POSICIÓN EN EL MUNDO (world_pos) para las coordenadas
    vec3 tex_x = texture(tex, world_pos.yz * scale).rgb; // Proyección X (usa Coords YZ)
    vec3 tex_y = texture(tex, world_pos.xz * scale).rgb; // Proyección Y (usa Coords XZ)
    vec3 tex_z = texture(tex, world_pos.xy * scale).rgb; // Proyección Z (usa Coords XY)

    // 3. Mezclar las tres texturas usando los pesos
    // Si la normal apunta a X, weights.x será 1 y el resto 0.
    return tex_x * weights.x + tex_y * weights.y + tex_z * weights.z;
}


// --- Función Fragment ---
// Se ejecuta para cada píxel del objeto.
void fragment() {
    
    // Obtenemos el color de la roca y del musgo usando nuestra función triplanar
    // NODE_POSITION_WORLD es la posición del píxel en el mundo.
    // NORMAL es la dirección (normal) del píxel en el mundo.
    vec3 moss_color = triplanar_texture(texture_moss, NODE_POSITION_WORLD, NORMAL);
    vec3 rock_color = triplanar_texture(texture_rock, NODE_POSITION_WORLD, NORMAL);

    // --- Lógica de Mezcla (Blend) ---
    // NORMAL.y nos dice qué tan "hacia arriba" (eje Y) apunta el píxel.
    // 1.0 = Totalmente hacia arriba (cielo)
    // 0.0 = Totalmente vertical (pared)
    // -1.0 = Totalmente hacia abajo (suelo)
    
    // 

    // Usamos smoothstep para crear un factor de mezcla (0.0 a 1.0)
    // basado en la dirección Y de la normal.
    float blend_factor = smoothstep(
        blend_offset - blend_sharpness, // Límite inferior de la mezcla
        blend_offset + blend_sharpness, // Límite superior de la mezcla
        NORMAL.y                        // El valor que estamos comprobando
    );

    // Mezclamos (mix) el color de roca y musgo usando el 'blend_factor'.
    // Si blend_factor es 0.0, es 100% roca.
    // Si blend_factor es 1.0, es 100% musgo.
    vec3 final_color = mix(rock_color, moss_color, blend_factor);

    // Asignamos el resultado final al color del objeto (Albedo)
    ALBEDO = final_color;
}