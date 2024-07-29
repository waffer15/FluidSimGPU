#[compute]
#version 450

layout(local_size_x = 1024, local_size_y = 1, local_size_z = 1) in;

#include "shared_data.glsl"

void collideWithWorldBoundary(inout vec2 my_pos, inout vec2 my_prev_pos, inout vec2 my_vel) {
    // float anti_stick = params.interaction_radius * length(my_pos) * params.delta_time * 1;
    float anti_stick = 0.05 * params.delta_time;
    if (my_pos.x < 0) {
        my_pos.x = 0;
        my_prev_pos.x = -anti_stick;
    }
    if (my_pos.y < 0) {
        my_pos.y = 0;
        my_prev_pos.y = -anti_stick;
    }
    if (my_pos.x >= params.viewport_x) {
        my_pos.x = params.viewport_x;
        my_prev_pos.x = params.viewport_x + anti_stick;
    }
    if (my_pos.y >= params.viewport_y) {
        my_pos.y = params.viewport_y;
        my_prev_pos.y = params.viewport_y + anti_stick;
    }
}

void applyGravity(inout vec2 my_vel, vec2 my_pos) {
    vec2 gravityAccel = vec2(0, params.gravity);
    int interactionInputRadius = 100;
    float inputStrength = 10;
    vec2 mouse_pos = vec2(params.mouse_x, params.mouse_y);

    if (params.mouse_down > 0) {
		vec2 inputPointOffset = mouse_pos - my_pos;
		float sqrDst = dot(inputPointOffset, inputPointOffset);
		if (sqrDst < interactionInputRadius * interactionInputRadius)
		{
			float dst = sqrt(sqrDst);
			float edgeT = (dst / interactionInputRadius);
			float centreT = 1 - edgeT;
			vec2 dirToCentre = inputPointOffset / dst;

			float gravityWeight = 1 - (centreT * inputStrength);
			vec2 accel = gravityAccel * gravityWeight + dirToCentre * centreT * inputStrength;
			accel -= my_vel * centreT;
			my_vel += params.delta_time * accel;
         return;
		}
	}
   my_vel += params.delta_time * gravityAccel;    
}

void predictPosition(inout vec2 my_pos, inout vec2 my_prev_pos, vec2 my_vel) {
    my_prev_pos = vec2(my_pos.x, my_pos.y);
    my_pos += my_vel * params.delta_time * params.velocity_damping;
}

void computeNextVelocity(inout vec2 my_vel, vec2 my_pos, vec2 my_prev_pos) {
   float max_vel = 100;
   vec2 next_vel = (my_pos - my_prev_pos) / params.delta_time;
   if (length(next_vel) < max_vel)
      my_vel = next_vel;
}

void doubleDensityRelaxation(inout vec2 my_pos, int my_index) {
    float interaction_radius = params.interaction_radius;
    float k = params.k;
    float k_near = params.k_near;
    float rest_density = params.rest_density;

    float density = 0.0;
	float density_near = 0.0;
    for(int i = 0; i < params.num_particles; i++) {
        if (i == my_index) continue;

        vec2 rij = fluid_pos.data[i] - my_pos;
        float q = length(rij) / interaction_radius;
        if (q < 1) {
            float one_minus_q = 1 - q;
            density += one_minus_q * one_minus_q;
            density_near += one_minus_q * one_minus_q * one_minus_q;
        }
    }

    float pressure = k * (density - rest_density);
    float pressure_near = k_near * density_near;
    vec2 particle_a_displacement = vec2(0, 0);

    for(int i = 0; i < params.num_particles; i++) {
        if (i == my_index) continue;

        vec2 rij = fluid_pos.data[i] - my_pos;
        float q = length(rij) / interaction_radius;
        if (q < 1) {
            rij = normalize(rij);
            float displacement_term = params.delta_time * params.delta_time * (pressure * (1 - q) + pressure_near * (1 - q) * (1 - q));
            vec2 d = rij * displacement_term;

            // boid_pos.data[i] += d * 0.5 * 1;
            particle_a_displacement -= d * 0.5;
        }
    }
    my_pos += particle_a_displacement;
}

void main() {
    int my_index = int(gl_GlobalInvocationID.x);
    if(my_index >= params.num_particles) return;

    vec2 my_pos = fluid_pos.data[my_index];
    vec2 my_prev_pos = predicted_pos.data[my_index];
    vec2 my_vel = fluid_vel.data[my_index];

    applyGravity(my_vel, my_pos);
    barrier();
    predictPosition(my_pos, my_prev_pos, my_vel);
    barrier();
    doubleDensityRelaxation(my_pos, my_index);
    barrier();
    collideWithWorldBoundary(my_pos, my_prev_pos, my_vel);
    barrier();
    computeNextVelocity(my_vel, my_pos, my_prev_pos);
    barrier();

    fluid_vel.data[my_index] = my_vel;
    fluid_pos.data[my_index] = my_pos;
    predicted_pos.data[my_index] = my_prev_pos;
    
    ivec2 pixel_pos = ivec2(int(mod(my_index, params.image_size)), int(my_index / params.image_size));
    imageStore(fluid_data, pixel_pos,vec4(my_pos.x, my_pos.y, 0, 0));
}