shader_type particles;

render_mode disable_velocity;

uniform float lifetime = 2.0;
uniform vec3 emission_box_extents = vec3(0.5, 0.2, 0.5);
uniform float spread = 15.0;

// Función hash para generar números aleatorios
float hash(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffff);
}

void start() {
    uint seed = NUMBER + uint(TIME * 1000.0);
    
    // Inicializar contador de vida
    CUSTOM.y = 0.0;
    
    // Posición inicial aleatoria en la proa
    TRANSFORM[3].xyz = vec3(
        (hash(seed) - 0.5) * emission_box_extents.x * 2.0,
        (hash(seed * 2U) - 0.5) * emission_box_extents.y * 2.0,
        (hash(seed * 3U) - 0.5) * emission_box_extents.z * 2.0
    );
    
    // Velocidad inicial hacia atrás y arriba
    VELOCITY = vec3(
        (hash(seed * 4U) - 0.5) * spread,
        hash(seed * 5U) * 2.0,
        -5.0 + (hash(seed * 6U) - 0.5) * spread
    );
    
    // Tamaño aleatorio
    float random_scale = 0.3 + hash(seed * 7U) * 0.4;
    TRANSFORM[0].xyz *= random_scale;
    TRANSFORM[1].xyz *= random_scale;
    TRANSFORM[2].xyz *= random_scale;
}

void process() {
    // Gravedad y desaceleración
    VELOCITY.y -= 9.8 * DELTA * 0.5;
    VELOCITY *= 0.98;
    
    // Calcular progreso de vida basado en CUSTOM.y que almacena el tiempo
    CUSTOM.y += DELTA;
    float life_percent = CUSTOM.y / lifetime;
    
    // Fade out al final de la vida
    float fade = 1.0 - life_percent;
    COLOR.a = fade * fade;
    
    // Ligero cambio de tamaño (se encoge)
    float scale_factor = 1.0 - life_percent * 0.3;
    TRANSFORM[0] *= scale_factor;
    TRANSFORM[1] *= scale_factor;
    TRANSFORM[2] *= scale_factor;
}