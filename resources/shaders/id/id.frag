#version 460 
#extension GL_ARB_separate_shader_objects : enable 
#extension GL_ARB_shading_language_420pack : enable 

layout (push_constant) uniform ID {
    uvec2 id;
} inId; 

layout (location = 0) out uvec2 outId; 

void main() { 
    outId = inId.id;
}  