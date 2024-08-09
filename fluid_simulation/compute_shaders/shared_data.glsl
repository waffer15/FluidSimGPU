layout(set = 0, binding = 0, std430) restrict buffer Position {
    vec2 data[];
} fluid_pos;

layout(set = 0, binding = 1, std430) restrict buffer PredictedPositions {
   vec2 data[];
} predicted_pos;

layout(set = 0, binding = 2, std430) restrict buffer Velocity {
    vec2 data[];
} fluid_vel;

layout(rgba16f, binding = 3) uniform image2D fluid_data;

layout(set = 0, binding = 4, std430) restrict buffer Params{
   float num_particles;
   float image_size;
   float viewport_x;
   float viewport_y;
   float delta_time;
   float velocity_damping;
   float interaction_radius;
   float k;
   float k_near;
   float rest_density;
   float gravity;
   int mouse_down;
   float mouse_x;
   float mouse_y;
   float viscous_beta;
   float viscous_sigma;
} params;