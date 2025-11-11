shader_type spatial;

// --- Parámetros (Ajustables desde el Inspector) ---

// 1. Texturas
uniform sampler2D tex_grass; // Textura de pasto (Albedo)
uniform sampler2D tex_rock;  // Textura de roca (Albedo)
uniform sampler2D tex_sand;  // Textura de arena (Albedo)

// Opcional: Mapas de Normales/Rugosidad para más realismo
// uniform sampler2D tex_grass_normal;
// uniform sampler2D tex_rock_normal;
// uniform sampler2D tex_sand_normal;

// 2. Control de Mezcla (Sintaxis Godot 4)
uniform float uv_scale = 5.0;

uniform float slope_sharpness = 10.0; // @hint_range(1.0, 50.0)
uniform float sand_height = 1.5; // @hint_range(-10.0, 20.0)
uniform float sand_blend_range = 2.0; // @hint_range(0.1, 10.0)


// --- Datos del Vértice ---
// Estos 'varyings' pasan datos del vertex() al fragment()
varying vec3 world_pos;
varying float slope_blend;
varying float height_blend;
varying vec2 scaled_uv;
varying vec4 biome_color;


void vertex() {
	// 1. Calcular la posición global del vértice
	// ¡CORRECCIÓN! En Godot 4 se usa MODEL_MATRIX, no WORLD_MATRIX
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// 2. Calcular la pendiente (slope)
	// NORMAL.y es 1.0 si es plano (apunta hacia arriba)
	// NORMAL.y es 0.0 si es vertical (apunta de lado)
	// Usamos pow() para controlar la "dureza" de la transición
	float slope = 1.0 - NORMAL.y;
	slope_blend = pow(slope, slope_sharpness);
	
	// 3. Calcular la mezcla de altura (para la arena)
	// smoothstep(min, max, valor) -> 0.0 si valor < min, 1.0 si valor > max
	// Queremos 1.0 (arena) si estamos ABAJO, 0.0 (tierra) si estamos ARRIBA.
	height_blend = smoothstep(sand_height + sand_blend_range, sand_height - sand_blend_range, world_pos.y);
	
	// 4. Escalar los UVs para que las texturas se repitan
	scaled_uv = UV * uv_scale;
	
	// 5. Pasar el color del bioma (que viene de GDScript)
	biome_color = COLOR;
}

void fragment() {
	// --- Muestreo de Texturas ---
	vec4 grass_col = texture(tex_grass, scaled_uv);
	vec4 rock_col = texture(tex_rock, scaled_uv);
	vec4 sand_col = texture(tex_sand, scaled_uv);

	// --- Lógica de Mezcla (Splatmapping) ---
	
	// 1. Mezcla Pasto y Roca (basado en la pendiente)
	// mix(a, b, peso) -> 'a' si peso=0, 'b' si peso=1
	vec4 grass_rock_mix = mix(grass_col, rock_col, slope_blend);
	
	// 2. Mezcla el resultado (Pasto/Roca) con la Arena (basado en la altura)
	vec4 final_texture = mix(grass_rock_mix, sand_col, height_blend);
	
	// 3. Aplicar el tinte del Bioma
	// Multiplicamos el color de la textura por el color del vértice
	ALBEDO = final_texture.rgb * biome_color.rgb;
	
	// --- Otros valores PBR (simplificado) ---
	METALLIC = 0.0;
	// Puedes hacer 'mix' de la rugosidad también
	ROUGHNESS = 0.8;
}