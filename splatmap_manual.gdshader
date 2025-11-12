shader_type spatial;

// --- Parámetros (Ajustables desde el Inspector) ---

// 1. Texturas de Detalle
uniform sampler2D tex_grass; // Textura de pasto
uniform sampler2D tex_rock;  // Textura de roca
uniform sampler2D tex_sand;  // Textura de arena

// 2. Textura de Control (¡La nueva!)
uniform sampler2D tex_splatmap; // R=Roca, G=Arena, Base=Pasto

// 3. Control de Tiling
uniform float uv_scale = 5.0;

// --- Datos del Vértice ---
varying vec2 scaled_uv; // UV para las texturas de detalle (tileables)
varying vec2 splat_uv;  // UV para la textura splatmap (no tileable)
varying vec4 biome_color; // Tinte del bioma


void vertex() {
	// 1. UVs para las texturas de detalle (se repiten)
	scaled_uv = UV * uv_scale;
	
	// 2. UVs para el splatmap (coincide 1:1 con el mesh)
	splat_uv = UV;
	
	// 3. Pasar el color del bioma
	biome_color = COLOR;
}

void fragment() {
	// --- Muestreo de Texturas ---
	vec4 grass_col = texture(tex_grass, scaled_uv);
	vec4 rock_col = texture(tex_rock, scaled_uv);
	vec4 sand_col = texture(tex_sand, scaled_uv);
	
	// --- Muestreo del Splatmap ---
	// Leemos los pesos de nuestra textura de control
	vec4 splat_weights = texture(tex_splatmap, splat_uv);

	// --- Lógica de Mezcla ---
	// Asignamos nuestros canales a los pesos:
	float rock_weight = splat_weights.r;  // Canal Rojo = Roca
	float sand_weight = splat_weights.g;  // Canal Verde = Arena
	
	// El Pasto es la base. Su peso es lo que "sobra".
	float grass_weight = 1.0 - clamp(rock_weight + sand_weight, 0.0, 1.0);
	
	// Mezclamos todo usando los pesos
	vec4 final_texture = (grass_col * grass_weight) + 
	                     (rock_col * rock_weight) + 
	                     (sand_col * sand_weight);
	
	// 3. Aplicar el tinte del Bioma
	ALBEDO = final_texture.rgb * biome_color.rgb;
	
	METALLIC = 0.0;
	ROUGHNESS = 0.8; // Puedes mejorar esto muestreando mapas de rugosidad
}