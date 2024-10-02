#[compute]
#version 450

layout(local_size_x = 1024, local_size_y = 1, local_size_z = 1) in;

#include "shared_data.glsl"


void collideWithWorldBoundary(int my_index) {
    float offset = 5;
    float boundaryMul = 0.5 * params.delta_time * params.delta_time;
    float boundaryMinX = offset;
    float boundaryMaxX = params.viewport_x - offset;
    float boundaryMinY = offset;
    float boundaryMaxY = params.viewport_y - offset;

    float kWallStickiness = 0.5;
    float kWallStickDist = 2;
    float stickMinX = boundaryMinX + kWallStickDist;
    float stickMaxX = boundaryMaxX - kWallStickDist;
    float stickMinY = boundaryMinY + kWallStickDist;
    float stickMaxY = boundaryMaxY - kWallStickDist;


    vec2 my_pos = fluid_pos.data[my_index];
    if (my_pos.x < boundaryMinX) {
        fluid_pos.data[my_index].x += boundaryMul * (boundaryMinX - my_pos.x);
    } else if (my_pos.x > boundaryMaxX) {
        fluid_pos.data[my_index].x += boundaryMul * (boundaryMaxX - my_pos.x);
    }

    if (my_pos.y < boundaryMinY) {
        fluid_pos.data[my_index].y += boundaryMul * (boundaryMinY - my_pos.y);
    } else if (my_pos.y > boundaryMaxY) {
        fluid_pos.data[my_index].y += boundaryMul * (boundaryMaxY - my_pos.y);
    }
  }


void applyGravity(int index) {
    vec2 my_pos = fluid_pos.data[index];
    vec2 my_vel = fluid_vel.data[index];

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
			fluid_vel.data[index] += params.delta_time * accel;
         return;
		}
	}
    fluid_vel.data[index] += params.delta_time * gravityAccel;    
}

void predictPosition(int my_index) {
    vec2 my_pos = fluid_pos.data[my_index];
    vec2 my_vel = fluid_vel.data[my_index];

    predicted_pos.data[my_index] = vec2(my_pos.x, my_pos.y);
    fluid_pos.data[my_index] += my_vel * params.delta_time * params.velocity_damping;
}

void computeNextVelocity(int my_index) {
    float max_v = 50;

    vec2 v = (fluid_pos.data[my_index] - predicted_pos.data[my_index]) / params.delta_time;
    if (length(v) > max_v)
        fluid_vel.data[my_index] = normalize(v) * max_v;
    else
        fluid_vel.data[my_index] = v;
    // fluid_vel.data[my_index] = (fluid_pos.data[my_index] - predicted_pos.data[my_index]) / params.delta_time;
}

void doubleDensityRelaxation(int my_index) {
    vec2 my_pos = fluid_pos.data[my_index];

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
            rij = rij / length(rij);
            float displacement_term = params.delta_time * params.delta_time * (pressure * (1 - q) + pressure_near * (1 - q) * (1 - q));
            vec2 d = rij * displacement_term;

            // boid_pos.data[i] += d * 0.5 * 1;
            particle_a_displacement -= d * 0.5;
        }
    }
    fluid_pos.data[my_index] += particle_a_displacement;
}

void applyViscosity(int my_index) {
    float sigma = params.viscous_sigma;
    float beta = params.viscous_beta;

    vec2 my_pos = fluid_pos.data[my_index];
    vec2 my_vel = fluid_vel.data[my_index];

    for(int i = 0; i < params.num_particles; i++) {
        if (i == my_index) continue;
        vec2 neighbour_pos = fluid_pos.data[i];
        vec2 neighbour_vel = fluid_vel.data[i];

        vec2 rij = neighbour_pos - my_pos;
        float q = length(rij) / params.interaction_radius;

        if (q < 1) {
            rij = normalize(rij);
            float u = dot(my_vel - neighbour_vel, rij);

            if (u > 0) {
                float ITerm = params.delta_time * (1 - q) * (sigma * u + beta * u * u);
                vec2 I = rij * ITerm;
                fluid_vel.data[my_index] -=  I * 0.5;
            }
        }
    }
}

void mixColors(int my_index) {
    vec4 my_color = particle_colors.data[my_index];
    vec2 my_pos = fluid_pos.data[my_index];
    float interaction_radius = params.interaction_radius;
    float color_mix_factor = 0.05; // Adjust the speed of color mixing here

    vec4 accumulated_color = vec4(0.0);
    float neighbor_count = 0.0;

    for(int i = 0; i < params.num_particles; i++) {
        if (i == my_index) continue;

        vec2 neighbor_pos = fluid_pos.data[i];
        float d = length(neighbor_pos - my_pos);

        if (d < interaction_radius) {
            vec4 neighbor_color = particle_colors.data[i];
            float distance_factor = 1.0 - (d / interaction_radius); // Closer particles influence more
            accumulated_color += neighbor_color * distance_factor;
            neighbor_count += distance_factor;
        }
    }

    if (neighbor_count > 0.0) {
        vec4 average_neighbor_color = accumulated_color / neighbor_count;
        particle_colors.data[my_index] = mix(my_color, average_neighbor_color, color_mix_factor);
    }
}

void collideWithMugCollider(int my_index) {
    vec2 my_pos = fluid_pos.data[my_index];
    vec2 my_vel = fluid_vel.data[my_index];

    // Define the particle radius; adjust as needed
    float particle_radius = params.interaction_radius * 0.5;

    // Get the number of vertices in the mug collider
    int num_vertices = 8;

    // Loop over each edge of the mug collider polygon
    for(int i = 0; i < num_vertices; i++) {
        vec2 A = mug_collider.data[i];
        vec2 B = mug_collider.data[(i + 1) % num_vertices]; // Wrap around to first vertex

        // Compute the vector from A to B and from A to the particle
        vec2 AB = B - A;
        vec2 AP = my_pos - A;

        // Project AP onto AB to find the closest point on the edge
        float t = dot(AP, AB) / dot(AB, AB);
        t = clamp(t, 0.0, 1.0);

        vec2 closest_point = A + t * AB;

        // Compute the vector from the closest point to the particle
        vec2 distance_vec = my_pos - closest_point;
        float d = length(distance_vec);

        // Check for collision
        if(d < particle_radius) {
            // Compute penetration depth
            float penetration = particle_radius - d;

            // Compute collision normal
            vec2 collision_normal = normalize(distance_vec);

            // Adjust position to resolve penetration
            my_pos += collision_normal * penetration;

            // Reflect velocity (simple collision response)
            my_vel = my_vel - 2.0 * dot(my_vel, collision_normal) * collision_normal;

            // Optionally, apply damping or friction here
        }
    }

    // Update the particle's position and velocity
    fluid_pos.data[my_index] = my_pos;
    fluid_vel.data[my_index] = my_vel;
}


void main() {
    int my_index = int(gl_GlobalInvocationID.x);
    if(my_index >= params.num_particles) return;

    applyGravity(my_index);
    barrier();
    applyViscosity(my_index);
    barrier();
    mixColors(my_index);
    barrier();
    predictPosition(my_index);
    barrier();
    doubleDensityRelaxation(my_index);
    barrier();
    collideWithWorldBoundary(my_index);
    barrier();
    collideWithMugCollider(my_index);
    barrier();
    computeNextVelocity(my_index);
    barrier();

    vec2 my_pos = fluid_pos.data[my_index];

    ivec2 pixel_pos = ivec2(int(mod(my_index, params.image_size)), int(my_index / params.image_size));
    imageStore(fluid_data, pixel_pos, vec4(my_pos.x, my_pos.y, 0, 0));

    vec4 my_color = particle_colors.data[my_index];
    imageStore(fluid_color, pixel_pos, my_color);
}