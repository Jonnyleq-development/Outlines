#include "ReShade.fxh"

uniform int OutlineEdgeDetection <
	ui_type = "combo";
	ui_label = "Edge Detection Source";
	ui_items = "Depth buffer\0Color buffer\0";
> = 0;

uniform bool OutlineCustomBackground <
	ui_label = "Use Custom Background Color";
> = false;

uniform float3 OutlineBackgroundColor <
	ui_type = "color";
	ui_label = "Background Color";
> = float3(1.0, 1.0, 1.0);

uniform float3 OutlineColor <
	ui_type = "color";
	ui_label = "Outline Color";
> = float3(0.0, 0.0, 0.0);

uniform float OutlineAccuracy <
	ui_type = "drag";
	ui_label = "Accuracy";
	ui_min = 0.1; ui_max = 100.0;
> = 1.0;

uniform float OutlineThreshold <
	ui_type = "drag";
	ui_label = "Threshold";
	ui_min = 0.0; ui_max = 10.0;
> = 0.5;

uniform float OutlineOpacity <
	ui_type = "slider";
	ui_label = "Opacity";
	ui_min = 0.0; ui_max = 1.0;
> = 1.0;

uniform float OutlineDepthRange <
	ui_type = "drag";
	ui_label = "Depth Range";
	ui_tooltip = "How far you're able to see the outlines.";
	ui_min = 0.0001; ui_max = 1.0;
	ui_step = 0.0001;
> = 0.05;

uniform bool OutlineInvertDepth <
	ui_label = "Invert Depth Direction";
	ui_tooltip = "Enable this if the Depth Threshold / Fade settings remove NEAR outlines instead of FAR ones.";
> = false;

uniform bool OutlineUseDepthThreshold <
	ui_label = "Hide Outlines Beyond Depth Threshold";
> = false;

uniform float OutlineDepthThreshold <
	ui_type = "slider";
	ui_label = "Depth Threshold";
	ui_min = 0.0; ui_max = 1.0;
> = 0.5;

uniform bool OutlineUseFading <
	ui_label = "Fade Outlines With Distance";
> = false;

uniform float OutlineFadeStart <
	ui_type = "slider";
	ui_label = "Fade Start Distance";
	ui_tooltip = "Outlines are fully visible up to this distance and begin fading after it.";
	ui_min = 0.0; ui_max = 1.0;
	ui_step = 0.001;
> = 0.3;

uniform float OutlineFadeEnd <
	ui_type = "slider";
	ui_label = "Fade End Distance";
	ui_tooltip = "Outlines are completely gone at and beyond this distance.";
	ui_min = 0.0; ui_max = 1.0;
	ui_step = 0.001;
> = 0.6;

uniform float OutlineFadeCurve <
	ui_type = "slider";
	ui_label = "Fade Curve";
	ui_tooltip = "Higher values make the fade start later and end sharper, keep near 0.4-0.8 for a gradual fade.";
	ui_min = 0.1; ui_max = 5.0;
> = 1.0;

namespace Jonny
{
	texture NormalizedDepthTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
	sampler NormalizedDepth { Texture = NormalizedDepthTex; };

	void PS_NormalizeDepth(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 normalizedDepth : SV_Target)
	{
		float4 depth = float4(
			ReShade::GetLinearizedDepth(texcoord + float2(BUFFER_RCP_WIDTH, 0.0)),
			ReShade::GetLinearizedDepth(texcoord - float2(BUFFER_RCP_WIDTH, 0.0)),
			ReShade::GetLinearizedDepth(texcoord + float2(0.0, BUFFER_RCP_HEIGHT)),
			ReShade::GetLinearizedDepth(texcoord - float2(0.0, BUFFER_RCP_HEIGHT)));

		float2 delta = float2(depth.x - depth.y, depth.z - depth.w) * float2(BUFFER_WIDTH, BUFFER_HEIGHT);

		normalizedDepth = float4(normalize(float3(delta, 1.0)), 1.0);
	}

	float3 SampleED(float2 uv)
	{
		if (OutlineEdgeDetection == 0)
			return tex2D(NormalizedDepth, uv).rgb;
		return tex2D(ReShade::BackBuffer, uv).rgb;
	}

	float3 PS_Outline(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
	{
		float3 backbuffer = tex2D(ReShade::BackBuffer, texcoord).rgb;
		float3 bg = OutlineCustomBackground ? OutlineBackgroundColor : backbuffer;
		float3 color = bg;

		// image intensity function
		static const float3 Gx[3] =
		{
			float3(-1.0, 0.0, 1.0),
			float3(-2.0, 0.0, 2.0),
			float3(-1.0, 0.0, 1.0)
		};

		static const float3 Gy[3] =
		{
			float3( 1.0,  2.0,  1.0),
			float3( 0.0,  0.0,  0.0),
			float3(-1.0, -2.0, -1.0)
		};

		float3 dotx = 0.0;
		float3 doty = 0.0;

		// edge detection
		[unroll]
		for (int i = 0; i < 3; i++)
		{
			float j = i - 1;
			dotx += Gx[i].x * SampleED(texcoord + float2(-BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT * j));
			dotx += Gx[i].y * SampleED(texcoord + float2(            0.0, BUFFER_RCP_HEIGHT * j));
			dotx += Gx[i].z * SampleED(texcoord + float2( BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT * j));

			doty += Gy[i].x * SampleED(texcoord + float2(-BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT * j));
			doty += Gy[i].y * SampleED(texcoord + float2(            0.0, BUFFER_RCP_HEIGHT * j));
			doty += Gy[i].z * SampleED(texcoord + float2( BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT * j));
		}

		// more edge detection
		dotx *= OutlineAccuracy;
		doty *= OutlineAccuracy;

		// custom color when weight over threshold
		float edge = sqrt(dot(dotx, dotx) + dot(doty, doty)) >= OutlineThreshold ? 1.0 : 0.0;
		color = lerp(color, OutlineColor, edge);

		// opacity
		color = lerp(bg, color, OutlineOpacity);

		// 1.0 = Depth Range
		float depth = saturate(ReShade::GetLinearizedDepth(texcoord) / OutlineDepthRange);
		if (OutlineInvertDepth)
			depth = 1.0 - depth;

		// depth to cut off lines
		if (OutlineUseDepthThreshold)
			color = depth > OutlineDepthThreshold ? bg : color;

		// depth to fade lines
		if (OutlineUseFading)
		{
			float fadeFactor = saturate((depth - OutlineFadeStart) / max(OutlineFadeEnd - OutlineFadeStart, 0.0001));
			fadeFactor = fadeFactor * fadeFactor * (3.0 - 2.0 * fadeFactor); // smoothstep: eases in and out, no hard edge
			fadeFactor = pow(fadeFactor, OutlineFadeCurve);
			color = lerp(color, bg, fadeFactor);
		}

		return color;
	}

	technique Outlines
	{
		pass DepthNormalization
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_NormalizeDepth;
			RenderTarget = NormalizedDepthTex;
		}

		pass Outline
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_Outline;
		}
	}
}
