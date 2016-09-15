// [ret, data] = PQC_readBuffer(device)
// data = data stored in buffer.

#include <windows.h>
#include <stdint.h>
#include "mex.h"
#include "th260defin.h"
#include "th260lib.h"
#include "errorcodes.h"

//GLOBALS?
long long oflcorrection;
long long truensync, truetime;
int m, c;
bool photon, marker;


void ProcessHHT3(unsigned int TTTRRecord, int HHVersion)
{
    const int T3WRAPAROUND = 1024;
    union {
        DWORD allbits;
        struct  {
            unsigned nsync    :10;  // numer of sync period
            unsigned dtime    :15;    // delay from last sync in units of chosen resolution
            unsigned channel  :6;
            unsigned special  :1;
        } bits;
    } T3Rec;
    T3Rec.allbits = TTTRRecord;
    marker = false;
    photon = false;
    if(T3Rec.bits.special==1)
    {
        if(T3Rec.bits.channel==0x3F) //overflow
        {
            //number of overflows is stored in nsync
            if((T3Rec.bits.nsync==0) || (HHVersion==1)) //if it is zero or old version it is an old style single oferflow
            {
                oflcorrection += (unsigned __int64)T3WRAPAROUND;
//         GotOverflow(1); //should never happen with new Firmware!
            }
            else
            {
                oflcorrection += (unsigned __int64)T3WRAPAROUND * T3Rec.bits.nsync;
//         GotOverflow(T3Rec.bits.nsync);
            }
        }
        if((T3Rec.bits.channel>=1)&&(T3Rec.bits.channel<=15)) //markers
        {
            truensync = oflcorrection + T3Rec.bits.nsync;
            //the time unit depends on sync period which can be obtained from the file header
            c = T3Rec.bits.channel;
            marker = true;
//       GotMarker(truensync, c);
        }
    }
    else //regular input channel
    {
        truensync = oflcorrection + T3Rec.bits.nsync;
        //the nsync time unit depends on sync period which can be obtained from the file header
        //the dtime unit depends on the resolution and can also be obtained from the file header
        c = T3Rec.bits.channel;
        m = T3Rec.bits.dtime;
        photon = true;
//       GotPhoton(truensync, c, m);
    }
}

void ProcessHHT2(unsigned int TTTRRecord, int HHVersion)
{
    const int T2WRAPAROUND_V1 = 33552000;
    const int T2WRAPAROUND_V2 = 33554432;
    union{
        DWORD   allbits;
        struct{ unsigned timetag  :25;
        unsigned channel  :6;
        unsigned special  :1; // or sync, if channel==0
        } bits;
    } T2Rec;
    T2Rec.allbits = TTTRRecord;
    marker = false;
    photon = false;
    if(T2Rec.bits.special==1)
    {
        if(T2Rec.bits.channel==0x3F) //an overflow record
        {
            if(HHVersion == 1)
            {
                oflcorrection += (unsigned __int64)T2WRAPAROUND_V1;
//                 GotOverflow(1);
            }
            else
            {
                //number of overflows is stored in timetag
                if(T2Rec.bits.timetag==0) //if it is zero it is an old style single overflow
                {
//                     GotOverflow(1);
                    oflcorrection += (unsigned __int64)T2WRAPAROUND_V2;  //should never happen with new Firmware!
                }
                else
                {
                    oflcorrection += (unsigned __int64)T2WRAPAROUND_V2 * T2Rec.bits.timetag;
//                     GotOverflow(T2Rec.bits.timetag);
                }
            }
        }
        
        if((T2Rec.bits.channel>=1)&&(T2Rec.bits.channel<=15)) //markers
        {
            truetime = oflcorrection + T2Rec.bits.timetag;
            //Note that actual marker tagging accuracy is only some ns.
            m = T2Rec.bits.channel;
            marker = true;
//     GotMarker(truetime, m);
        }
        
        if(T2Rec.bits.channel==0) //sync
        {
            truetime = oflcorrection + T2Rec.bits.timetag;
//     GotPhoton(truetime, 0, 0);
        }
    }
    else //regular input channel
    {
        truetime = oflcorrection + T2Rec.bits.timetag;
        c = T2Rec.bits.channel + 1;
        photon = true;
//     GotPhoton(truetime, c, 0);
    }
    
}



void mexFunction( int nlhs, mxArray *plhs[],
        int nrhs, const mxArray *prhs[] )
{
    
//     TTREADMAX 131072 
    char    Errorstring[40];
    int     flags, nRecords, retcode;
    int     ctcstatus;
    int     i;
    int     n_photons = 0;
    int     n_events = 0;
    mwSize  ndim;
    mwSize  dims[2];
    double  *dev, *ret;
    uint32_t buffer[TTREADMAX];
    long long  *photon_time_array; //[TTREADMAX];
    int     *photon_dtime_array; //[TTREADMAX];
    long long  *event_time_array; //[TTREADMAX];
    int     *photon_ch_array; //[TTREADMAX];
    int     *event_ch_array; //[TTREADMAX];
    uint32_t *buf;
    
    /* Check for proper number of arguments. */
    if(nrhs!=1) {
        mexErrMsgIdAndTxt( "MATLAB:PQC_readBuffer:invalidNumInputs",
                "1 input required.");
    } else if(nlhs>3) {
        mexErrMsgIdAndTxt( "MATLAB:PQC_readBuffer:maxlhs",
                "Too many output arguments.");
    }
    
    dev = mxGetPr(prhs[0]);
    //printf("Measurement start!\n");
    retcode = TH260_GetFlags((int)dev[0], &flags);
    if(retcode<0)
    {
        TH260_GetErrorString(Errorstring, retcode);
        printf("\nTH260_GetFlags error %d (%s). \n",retcode,Errorstring);
    }
    
    if (flags&FLAG_FIFOFULL)
    {
        printf("\nFiFo Overrun!\n");
    }
    
    retcode = TH260_ReadFiFo((int)dev[0],buffer,TTREADMAX,&nRecords);	//may return less!
    if(retcode<0)
    {
        TH260_GetErrorString(Errorstring, retcode);
        printf("\nTH260_ReadFiFo error %d (%s). \n",retcode,Errorstring);
        goto ex;
    }
    
    /////
    if(nRecords > 0)
    {
        n_photons = 0;
        n_events = 0;
        photon_time_array = mxCalloc(nRecords, sizeof(long long));
        photon_dtime_array = mxCalloc(nRecords, sizeof(int));
        photon_ch_array = mxCalloc(nRecords, sizeof(int));
        event_time_array = mxCalloc(nRecords, sizeof(long long));
        event_ch_array = mxCalloc(nRecords, sizeof(int));
        
        for (i=0; i<nRecords; i++)
        {
            ProcessHHT3(buffer[i], 2);
            //ProcessHHT2(TTTRRecord, 2);
            if (photon)
            {
                photon_time_array[n_photons] = truensync;
                photon_dtime_array[n_photons] = m;
                photon_ch_array[n_photons] = c;
                n_photons = n_photons + 1;
            }
            else if (marker) 
            {
                event_time_array[n_events] = truensync;
                event_ch_array[n_events] = c;
                n_events = n_events + 1;
            }
        }
        plhs[0] = mxCreateDoubleMatrix((mwSize)1, (mwSize)1, mxREAL);
        ret = mxGetPr(plhs[0]);
        ret[0] = (double)retcode;
        
        plhs[1] = mxCreateDoubleMatrix((mwSize)n_photons, (mwSize)3, mxREAL);
        ret = mxGetPr(plhs[1]);
        for (i=0; i<n_photons; i++)
            ret[i] = (double) photon_ch_array[i];
        for (i=0; i<n_photons; i++)
            ret[i + n_photons] = (double) photon_dtime_array[i];
        for (i=0; i<n_photons; i++)
            ret[i + n_photons*2] = (double) photon_time_array[i];
        
        plhs[2] = mxCreateDoubleMatrix((mwSize)n_events, (mwSize)2, mxREAL);
        ret = mxGetPr(plhs[2]);
        for (i=0; i<n_events; i++)
            ret[i] = (double) event_ch_array[i];
        for (i=0; i<n_events; i++)
            ret[i + n_events] = (double) event_time_array[i];
        
        mxFree(photon_time_array);
        mxFree(photon_dtime_array);
        mxFree(photon_ch_array);
        mxFree(event_time_array);
        mxFree(event_ch_array);
        
    }
    else
    {
        retcode = TH260_CTCStatus((int)dev[0], &ctcstatus);
        if(retcode<0)
        {
            TH260_GetErrorString(Errorstring, retcode);
            printf("\nTH260_CTCStatus error %d (%s). \n",retcode,Errorstring);
        }
        if (ctcstatus)
        {
            //printf("\nDone\n");
            retcode = -2;
        }
        
        goto ex;
    }
    
    
    ex:
        if (retcode < 0)
        {
            plhs[0] = mxCreateDoubleMatrix((mwSize)1, (mwSize)1, mxREAL);
            ret = mxGetPr(plhs[0]);
            ret[0] = (double)retcode;
            plhs[1] = mxCreateDoubleMatrix((mwSize)1, (mwSize)1, mxREAL);
            ret = mxGetPr(plhs[1]);    //within this loop you can also read the count rates if needed.
            plhs[2] = mxCreateDoubleMatrix((mwSize)1, (mwSize)1, mxREAL);
            ret = mxGetPr(plhs[2]);    //within this loop you can also read the count rates if needed.

        }
}