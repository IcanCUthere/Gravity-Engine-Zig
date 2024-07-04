#version 460
#extension GL_ARB_separate_shader_objects : enable 
#extension GL_ARB_shading_language_420pack : enable 

layout (std140, binding = 0) uniform matrices {
    mat4 model;
    mat4 view;
    mat4 projection;
} Matrices;

layout (location = 0) in vec3 inPosition;
layout (location = 1) in vec3 inNormal;
layout (location = 2) in vec2 inTexCoords;


layout(location = 0) out vec3 outNormal;
layout(location = 1) out vec3 outPos;
layout(location = 2) out vec2 outTexCoords;
layout(location = 3) out vec3 outLightPos;

void main() {
    gl_Position = Matrices.projection * Matrices.view * Matrices.model * vec4(inPosition, 1.0);
    outNormal = mat3(transpose(inverse(Matrices.view * Matrices.model))) * inNormal;
    outPos = vec3(Matrices.view * Matrices.model * vec4(inPosition, 1.0));  
    outTexCoords = inTexCoords;
    outLightPos = vec3(Matrices.view * vec4(0.0, 0.0, -400.0, 1.0));
}