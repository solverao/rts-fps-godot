// Define el tipo de shader como 'spatial' (para 3D)
shader_type spatial;

// --- Variables (Uniforms) ---
// Estas variables aparecerán en el Inspector de Godot
// para que puedas ajustarlas fácilmente.

// El color base del personaje
uniform vec4 albedo : source_color = vec4(1.0);
// El color que usarán las sombras
uniform vec4 shadow_color : source_color = vec4(0.3, 0.3, 0.3, 1.0);
// Define qué tan nítido es el borde entre luz y sombra
// 0.0 = muy nítido (cel-shading clásico)
// 0.5 = más suave (como en la imagen)
uniform float shadow_smoothness : hint_range(0.0, 1.0) = 0.1;

// --- Función Fragment ---
// Se ejecuta para cada píxel del objeto.
void fragment() {
    // Simplemente asignamos el color base al albedo.
    // La magia ocurrirá en la función light().
    ALBEDO = albedo.rgb;
}

// --- Función Light ---
// Se ejecuta para cada luz que afecta al píxel.
// Aquí es donde calculamos el sombreado "toon".
void light() {
    // NdotL es el producto punto entre la Normal de la superficie y la dirección de la Luz.
    // Es un valor entre 0.0 (luz de lado) y 1.0 (luz de frente).
    float NdotL = dot(NORMAL, LIGHT);

    // Usamos smoothstep para crear la banda de sombra.
    // Compara NdotL con un umbral (0.5).
    // Gracias a 'shadow_smoothness', la transición no es 100% dura,
    // sino que tiene un pequeño suavizado, que queda muy bien.
    float shadow_t = smoothstep(0.5 - shadow_smoothness, 0.5 + shadow_smoothness, NdotL);

    // 'shadow_t' será 0.0 si está en sombra, o 1.0 si está en luz.
    // Usamos mix() para mezclar (interpolar) entre el color de sombra y el de luz.
    // ATTENUATION es la energía y color de la luz (Godot nos lo da).
    // Multiplicamos el color de sombra por la atenuación para que las sombras
    // también reciban el color de la luz.
    DIFFUSE_LIGHT = mix(shadow_color.rgb * ATTENUATION, ATTENUATION, shadow_t);
}