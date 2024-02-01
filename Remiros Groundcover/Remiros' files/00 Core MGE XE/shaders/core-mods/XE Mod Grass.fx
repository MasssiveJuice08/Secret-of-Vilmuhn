
// XE Mod Grass.fx
// MGE XE 0.12.1
// Grass rendering. Can be used as a core mod.

#define GRASS_WRAP_LIGHTING_COEFF_W 0.6
#define GRASS_WRAP_LIGHTING_COEFF_N 1.5
#define GRASS_BACKLIGHTING_COEFF 0.4

//------------------------------------------------------------

// Basic noise
float bnoise( in float x )
{
    // setup    
    float i = floor(x);
    float f = frac(x);
    float s = sign(frac(x/2.0)-0.5);
    
    // use some hash to create a random value k in [0..1] from i
  //float k = hash(uint(i));
  //float k = 0.5+0.5*sin(i);
    float k = frac(i*.1731);

    // quartic polynomial
    return s*f*(f-1.0)*((16.0*k-4.0)*f*(f-1.0)-1.0);
}

// Grass displacement function, based on wind and player proximity

float2 grassDisplacement(float4 worldpos, float h)
{
    float v = length(windVec);
    float2 displace = 2 * windVec + 0.1;
    float2 harmonics = 0;
    
    float gtime = time * 0.5;

    float fi = 0.5;
    float cg = 3.14;
    float bi = 16.0;
    
    
    harmonics.x += abs(((fi * 1.0 + 0.03 * v) * sin(-2 * cg * (worldpos.x + worldpos.y + worldpos.z + gtime))) + bi * 1);
    
    harmonics.y += abs(((fi * 2.0 + 0.044 * v) * sin(-3 * cg *(worldpos.x + worldpos.y + worldpos.z + gtime))) + bi * 0.5);
    
    float d = length(worldpos.xy - footPos.xy);
    float2 stomp = 0;
    
    if(d < 150)
        stomp = (60 / d - 0.4) * (worldpos.xy - footPos.xy);

    return saturate(0.02 * h) * (harmonics * displace + stomp);
}

//------------------------------------------------------------
// Common functions

TransformedVert transformGrassVert(StatVertInstIn IN) {
    TransformedVert v;
    
    v.worldpos = instancedMul(IN.pos, IN.world0, IN.world1, IN.world2);
	float3 dist = v.worldpos.xyz - eyePos.xyz;
	dist = smoothstep(5300, 7300, length(dist) - 1900 *  saturate((bnoise(v.worldpos.x + v.worldpos.y ))));
    // Transforms with wind displacement
    v.worldpos.xy += IN.color.r * grassDisplacement(v.worldpos, IN.pos.z);
	v.worldpos.z -= 100 * dist;
    v.viewpos = mul(v.worldpos, view);
    v.pos = mul(v.viewpos, proj);

    // Decompress normal
    float4 normal = float4(normalize(2 * IN.normal.xyz - 1), 0);
    v.normal = instancedMul(normal, IN.world0, IN.world1, IN.world2);
    return v;
}

//------------------------------------------------------------
// Grass

struct GrassVertOut {
    float4 pos : POSITION;
    half2 texcoords : TEXCOORD0;
    half4 color : COLOR0;
    half4 fog : COLOR1;
    
    float4 shadow0pos : TEXCOORD1;
    float4 shadow1pos : TEXCOORD2;
};

GrassVertOut GrassInstVS(StatVertInstIn IN) {
    GrassVertOut OUT;
    TransformedVert v = transformGrassVert(IN);
    float3 eyevec = v.worldpos.xyz - eyePos.xyz;

    OUT.pos = v.pos;
    OUT.fog = fogMWColour(length(eyevec));

    // Lighting for two-sided rendering, no emissive
    float lambert = dot(v.normal.xyz, -sunVec);

	if(IN.color.r > 0.5) {
		float w = GRASS_WRAP_LIGHTING_COEFF_W;
		float n = GRASS_WRAP_LIGHTING_COEFF_N;
		lambert = dot(v.normal.xyz, -sunVec) * -sign(dot(eyevec, v.normal.xyz));
		lambert = pow(saturate((lambert + w) / (1.0f + w)), n) * (n + 1) / (2 * (1 + w)) + max(0.0, -1.0 * lambert) * GRASS_BACKLIGHTING_COEFF;
	}
	
	lambert = max(0.0, lambert);
	
    // Ignoring vertex colour due to problem with some grass mods
    OUT.color.rgb = sunCol * lambert + sunAmb;

    // Non-standard shadow luminance, to create sufficient contrast when ambient is high
    OUT.color.a = shadowSunEstimate(lambert);

    // Find position in light space, output light depth
    OUT.shadow0pos = mul(v.worldpos, shadowViewProj[0]);
    OUT.shadow1pos = mul(v.worldpos, shadowViewProj[1]);
    OUT.shadow0pos.z = OUT.shadow0pos.z / OUT.shadow0pos.w;
    OUT.shadow1pos.z = OUT.shadow1pos.z / OUT.shadow1pos.w;

    OUT.texcoords = IN.texcoords;
    return OUT;
}

float4 GrassPS(GrassVertOut IN): COLOR0 {
    float4 result = tex2D(sampBaseTex, IN.texcoords);
    result.rgb *= IN.color.rgb;
	//result.rgb = float3(1,0,0);
	
    // Alpha test early
    // Note: clip is not used here because at certain optimization levels,
    // the texkill is pushed to the very end of the function
    if(result.a < 64.0/255.0)
        discard;

    // Soft shadowing
    float dz = shadowDeltaZ(IN.shadow0pos, IN.shadow1pos);
    float v = shadowESM(dz);
 
    // Darken shadow area according to existing lighting (slightly towards blue)
    v *= IN.color.a;
    result.rgb *= 0.9 - v * shadecolor;
    
    // Fogging
    result.rgb = fogApply(result.rgb, IN.fog);
    
    // Alpha to coverage conversion
    result.a = calc_coverage(result.a, 128.0/255.0, 1.3);
    
    return result;
}

//------------------------------------------------------------
// Depth buffer output


DepthVertOut DepthGrassInstVS(StatVertInstIn IN) {
    DepthVertOut OUT;
    TransformedVert v = transformGrassVert(IN);

    OUT.pos = v.pos;
    OUT.depth = v.pos.w;
    OUT.alpha = 1;
    OUT.texcoords = IN.texcoords;

    return OUT;
}