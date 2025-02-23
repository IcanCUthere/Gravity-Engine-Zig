#version 460 
#extension GL_ARB_separate_shader_objects : enable 
#extension GL_ARB_shading_language_420pack : enable 

layout(location = 0) in vec2 inTexCoords;

layout (set = 1, binding = 0) uniform sampler2D texSampler;

layout (location = 0) out vec4 outFragColor; 

void main() { 
    outFragColor = texture(texSampler, inTexCoords);
}  