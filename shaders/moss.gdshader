shader_type spatial;

uniform sampler2D rock_albedo : source_color;
uniform sampler2D rock_normal : hint_normal;
uniform sampler2D rock_roughness : hint_default_white;

uniform sampler2D moss_albedo : source_color;
uniform sampler2D moss_normal : hint_normal;
uniform sampler2D moss_roughness : hint_default_white;

uniform float noise_scale = 0.5; // Escala del ruido para los parches
uniform float normal_y_influence = 2.0; // Cuánto influye la pendiente
uniform float moss_min_threshold = 0.3; // Umbral inferior para el musgo
uniform float moss_max_threshold = 0.7; // Umbral superior para el musgo

// Incluir tu función de ruido (por ejemplo, OpenSimplexNoise)
// Puedes encontrar implementaciones en línea o usar el Visual Shader para los nodos de ruido.
float var = opensimplex_noise3d(vec3 p); 

void fragment() {
    vec3 world_pos = VERTEX; // Posición del vértice en el espacio del mundo

    // 1. Obtener los valores de las texturas de roca y musgo
    vec4 rock_base_color = texture(rock_albedo, UV);
    vec3 rock_normal_map = texture(rock_normal, UV).rgb;
    float rock_rough = texture(rock_roughness, UV).r;

    vec4 moss_base_color = texture(moss_albedo, UV);
    vec3 moss_normal_map = texture(moss_normal, UV).rgb;
    float moss_rough = texture(moss_roughness, UV).r;

    // 2. Calcular el factor de mezcla para el musgo
    float noise_val = opensimplex_noise3d(world_pos * noise_scale);
    
    // Normal del píxel en espacio del mundo
    vec3 N = NORMAL; 

    // Combinar ruido con la influencia del eje Y
    // Usamos NORMAL.y para saber qué tan "hacia arriba" está la superficie
    float blend_factor = noise_val + (N.y * normal_y_influence);

    // Suavizar la transición del musgo
    float final_moss_blend = smoothstep(moss_min_threshold, moss_max_threshold, blend_factor);
    
    // 3. Mezclar los materiales
    ALBEDO = mix(rock_base_color.rgb, moss_base_color.rgb, final_moss_blend);
    NORMAL_MAP = mix(rock_normal_map, moss_normal_map, final_moss_blend);
    ROUGHNESS = mix(rock_rough, moss_rough, final_moss_blend);

    // Puedes añadir más mezcla para ORM (Occlusion, Roughness, Metallic) si usas esos canales.
}