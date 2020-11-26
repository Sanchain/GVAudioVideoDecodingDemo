#ifndef __FFMPEG_AV_CODEC_H__
#define __FFMPEG_AV_CODEC_H__

#ifdef __cplusplus
extern "C" {
#endif
    //G711 PCMA解码
    int G711A_AudioDecode(char* out_pOutput,int *out_pOutLen,
		const char* in_pFrameBuf, int in_nFrameSize);
    //G711 PCMU解码
    int G711U_AudioDecode(char* out_pOutput,int *out_pOutLen,
                           const char* in_pFrameBuf, int in_nFrameSize);
    //G711 PCMA编码
    int G711A_AudioEncode(unsigned char* in_pInput, unsigned int in_nInLen, unsigned char* out_pOutput, unsigned int*out_pOutLen);
    //G711 PCMU编码
    int G711U_AudioEncode(unsigned char* in_pInput, unsigned int in_nInLen, unsigned char* out_pOutput, unsigned int*out_pOutLen);
#ifdef __cplusplus
}
#endif
#endif // __FFMPEG_AV_CODEC_H__
