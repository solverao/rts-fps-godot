shader_type spatial;

// Colores de los diferentes tipos de tierra
uniform vec4 dark_dirt_color : source_color = vec4(0.25, 0.18, 0.12, 1.0);
uniform vec4 light_dirt_color : source_color = vec4(0.45, 0.35, 0.25, 1.0);
uniform vec4 sand_color : source_color = vec4(0.7, 0.65, 0.5, 1.0);
uniform vec4 rock_color : source_color = vec4(0.4, 0.4, 0.38, 1.0);

// Parámetros de material
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// Mezcla por altura
uniform float height_transition_1 : hint_range(-100.0, 100.0) = 5.0;
uniform float height_transition_2 : hint_range(-100.0, 100.0) = 15.0;
uniform float height_blend_smoothness : hint_range(0.1, 20.0) = 3.0;

// Mezcla por pendiente
uniform float slope_threshold : hint_range(0.0, 90.0) = 45.0;
uniform float slope_smoothness : hint_range(0.1, 20.0) = 10.0;

// Parámetros de ruido
uniform float noise_scale : hint_range(0.1, 10.0) = 2.0;
uniform float noise_detail_scale : hint_range(1.0, 50.0) = 15.0;
uniform float color_variation : hint_range(0.0, 1.0) = 0.3;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.5;

// Función de ruido Simplex 3D (aproximación)
vec3 mod289_3(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289_4(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289_4(((x*34.0)+1.0)*x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
    const vec2 C = vec2(1.0/6.0, 1.0/3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

    vec3 i  = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);

    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);

    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;

    i = mod289_3(i);
    vec4 p = permute(permute(permute(
        i.z + vec4(0.0, i1.z, i2.z, 1.0))
        + i.y + vec4(0.0, i1.y, i2.y, 1.0))
        + i.x + vec4(0.0, i1.x, i2.x, 1.0));

    float n_ = 0.142857142857;
    vec3 ns = n_ * D.wyz - D.xzx;

    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);

    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);

    vec4 x = x_ *ns.x + ns.yyyy;
    vec4 y = y_ *ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);

    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);

    vec4 s0 = floor(b0)*2.0 + 1.0;
    vec4 s1 = floor(b1)*2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));

    vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww;

    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);

    vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m*m, vec4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}

// Ruido fractal (FBM)
float fbm(vec3 pos, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;

    for(int i = 0; i < octaves; i++) {
        value += amplitude * snoise(pos * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }

    return value;
}

void fragment() {
    // Posición mundial
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

    // Altura y pendiente
    float height = world_pos.y;
    float slope = 1.0 - world_normal.y;
    float slope_angle = acos(world_normal.y);

    // Generar ruidos a diferentes escalas
    float noise_large = fbm(world_pos * noise_scale, 4);
    float noise_medium = fbm(world_pos * noise_scale * 3.0, 3);
    float noise_detail = fbm(world_pos * noise_detail_scale, 5);

    // Normalizar ruidos a 0-1
    noise_large = noise_large * 0.5 + 0.5;
    noise_medium = noise_medium * 0.5 + 0.5;
    noise_detail = noise_detail * 0.5 + 0.5;

    // ====== MEZCLA POR ALTURA ======
    // Tierra oscura -> clara
    float height_blend_1 = smoothstep(
        height_transition_1 - height_blend_smoothness,
        height_transition_1 + height_blend_smoothness,
        height + noise_large * height_blend_smoothness * 2.0
    );

    vec3 base_color = mix(dark_dirt_color.rgb, light_dirt_color.rgb, height_blend_1);

    // Clara -> arena
    float height_blend_2 = smoothstep(
        height_transition_2 - height_blend_smoothness,
        height_transition_2 + height_blend_smoothness,
        height + noise_large * height_blend_smoothness * 2.0
    );

    base_color = mix(base_color, sand_color.rgb, height_blend_2);

    // ====== MEZCLA POR PENDIENTE ======
    float slope_factor = smoothstep(
        radians(slope_threshold) - radians(slope_smoothness),
        radians(slope_threshold) + radians(slope_smoothness),
        slope_angle
    );

    vec3 final_color = mix(base_color, rock_color.rgb, slope_factor * 0.7);

    // ====== VARIACIÓN DE COLOR ======
    // Agregar manchas oscuras y claras
    float color_noise = noise_medium;
    final_color *= 1.0 + (color_noise - 0.5) * color_variation;

    // Detalles finos (pequeñas piedras, textura)
    final_color *= 1.0 + (noise_detail - 0.5) * 0.15;

    // Asegurar que el color esté en rango válido
    final_color = clamp(final_color, 0.0, 1.0);

    ALBEDO = final_color;

    // ====== NORMAL MAP PROCEDURAL ======
    // Crear bumps usando el ruido
    float bump = noise_detail * 2.0 - 1.0;
    vec3 bump_normal = vec3(0.0, 0.0, bump * bump_strength);
    NORMAL_MAP = bump_normal;

    // ====== ROUGHNESS VARIADO ======
    // Arena es más suave que tierra
    float rough_variation = mix(0.9, 0.6, height_blend_2);
    // Rocas son más rugosas
    rough_variation = mix(rough_variation, 0.95, slope_factor);

    ROUGHNESS = rough_variation * roughness;
    METALLIC = metallic;
    SPECULAR = 0.5;
}