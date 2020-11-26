
#include "AdpcmCodec.h"
#include "g711.h"
#include "string.h"
#ifdef __cplusplus
extern "C" {

#endif

int G711A_AudioDecode(char* out_pOutput,int *out_pOutLen,
                           const char* in_pFrameBuf, int in_nFrameSize)
    {

    if((in_nFrameSize <= 0) || (NULL== in_pFrameBuf))
        return -1;

    unsigned int out_size = (in_nFrameSize << 1);

    for(int i=0, nOffset=0; i<in_nFrameSize; i++)
    {
        int iLinear = alaw2linear(in_pFrameBuf[i]);
        memcpy(out_pOutput + nOffset, &iLinear, 2);
        nOffset += 2;
    }
    *out_pOutLen = out_size;

    return 1;
}

int G711U_AudioDecode(char* out_pOutput,int *out_pOutLen,
                           const char* in_pFrameBuf, int in_nFrameSize)
    {
    if((in_nFrameSize <= 0) || (NULL== in_pFrameBuf))
        return -1;
    
    unsigned int out_size = (in_nFrameSize << 1);
    
    for(int i=0, nOffset=0; i<in_nFrameSize; i++)
    {
        int iLinear = ulaw2linear(in_pFrameBuf[i]);
        memcpy(out_pOutput + nOffset, &iLinear, 2);
        nOffset += 2;
    }
    *out_pOutLen = out_size;
    
    return 1;
}
    
//G711 PCMA解码
int G711A_AudioEncode(unsigned char* in_pInput, unsigned int in_nInLen, unsigned char* out_pOutput, unsigned int*out_pOutLen)
{
    if(!in_pInput || !out_pOutput || in_nInLen <= 0)
        return -1;
    
    unsigned int out_size = (in_nInLen >> 1);
    uint8_t* pout_data = out_pOutput;
    int16_t* pin_data = (int16_t*)in_pInput;
    
    for(int i=0; i<out_size; i++)
    {
        pout_data[i] = linear2alaw(pin_data[i]);
    }
    
    *out_pOutLen = out_size;
    return 1;
}
    
//G711 PCMU编码
int G711U_AudioEncode(unsigned char* in_pInput, unsigned int in_nInLen, unsigned char* out_pOutput, unsigned int*out_pOutLen)
{
    if(!in_pInput || !out_pOutput || in_nInLen <= 0)
    {
        return -1;
    }

    unsigned int out_size = (in_nInLen >> 1);
    uint8_t* pout_data = out_pOutput;
    int16_t* pin_data = (int16_t*)in_pInput;
    
    for(int i=0; i<out_size; i++)
    {
        pout_data[i] = linear2ulaw(pin_data[i]);
    }
    
    *out_pOutLen = out_size;
    return 1;
}
    
#ifdef __cplusplus
}
#endif

