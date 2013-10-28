% function Peaks=my_fmrib_qrsdetect(ecg,fs)
%
% ecg = the ecg signal (a double 1-by-N or N-by-1 vector)
% fs = the samplerate of the signal (a double scalar)
%
%
% my_fmrib_qrsdetect is a function of which I actually stole the code! The
% thing that is different, is that I want to let this function work on a
% matlab array, instead of an EEG eeglab dataset. In other words, to have
% more of a low-level (see FieldTrip manual) function, instead of a
% 'middle/high-level' function, which is it now.
%
% for some reason or other, the outcome markers are place with an accuracy
% of 1/100th of a second even with a sampling rate of 1/1000. 
% This is no good if we wish to do some meaningful
% bcg correction. Furthermore, it seems like sometimes the markers are not
% placed correctly.
%
% So -apart from copying the code, I also added an extra realignment step
% to this function that changes the markers to have a obtain a 1/1000 sec
% accuracy (hopefully). See the bottom of this function; next to
% qrscorrect.m I call qrsbetteralign.m
%
% IN ADDITION, I do some consistency checking of the BCG artifacts while
% i'm at it. BCG artifacts that are not-so-good, I remove. therefore, I've
% also added an extra output variable called 'usabledata'. this should be a
% LOGICAL N-by-1 vector telling us which segments of the data are
% good/usable!
%
%
% an experimental part is also where I try a sort-of algorithm that could
% maybe work better.
%
% if the product of the extra realignment step already gives you a decent
% ECG template waveform, then maybe we can improve upon that with a sliding
% correlation window that tries to match it.
% this extra step is called:
%
% qrs_improvement_slidingwindow(Peaks,ecg,fs);
% 
%
%
% The original function, together with the appropriate references
% (i.e., reference at least Niazy06 if publucation if you use this function. 
%
% fmrib_qrsdetect() - Detect QRS peaks from ECG channel using combined
%   adaptive thresholding [Christov04,Niazy06]];
%


function [Peaks UsableData Correlations]=my_fmrib_qrsdetect(ecg,fs, verbose)

import misc.eta;

if ~goo.globals.get.Verbose,
    verbose = 0;
end

%
% This program detects QRS peaks from a ECG channel.  First a complex lead
%   is constructed by computing the Teager Energy Operator TEO [Kim04] and 
%   then computing an adaptive threshold for each sampling point using a 
%   slightly modified version of [Christov04]. Points passing the threshold 
%   are counted as peaks.  A correction algorithm [Niazy06] is then 
%   run (qrscorrect.m) which corrects for false positives and negatives 
%   and align the  peaks using correlation of the original ECG data.
%
% Usage:
%   >> peaks=fmrib_qrsdetect(EEG,ecgchan)
%
% Inputs:
%   EEG: EEGLAB data structure
%   ecgchan: The number of the ECG channel in the EEG data structure
%
% Ouptut:
%   peaks: index of QRS peak locations
%
%
%
% [Niazy06] R.K. Niazy, C.F. Beckmann, G.D. Iannetti, J.M. Brady, and 
%  S.M. Smith (2005) Removal of FMRI environment artifacts from EEG data 
%  using optimal basis sets. NeuroImage 28 (3), pages 720-737.
%
% [Christov04] Real time electrocardiogram QRS detection using combined 
%  adaptive threshold, Ivaylo I. Christov.  Biomedical Engineering Online, 
%  BioMed Central (2004). available at:
%  http://www.biomedical-engineering-online.com/content/3/1/28
%
% [Kim04] Improved ballistocardiac artifact removal from the 
%  electroencephalogram recored in FMRI, KH Kim, HW Yoon, HW Park. 
% J NeouroSience Methods 135 (2004) 193-203.
%
%
% Author: Rami Niazy, FMRIB Centre, University of Oxford.
%   
% Copyright (c) 2006 University of Oxford

% Copyright (C) 2006 University of Oxford
% Author:   Rami K. Niazy, FMRIB Centre
%           rami@fmrib.ox.ac.uk
%
% This program is free software; you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation; either version 2 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program; if not, write to the Free Software
% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

%   Feb 2013, Modified by German Gomez-Herrero
%   Add input argument verbose

%   JUNE 03, 2005
%   Released after testing

%   APR 11, 2005
%   Beta version with more adaptive F threshold

%   APR 6, 2005
%   Removed accidentaly pasted code (BIG BUG)

%  MAR 16, 2005
%   Fixed typos and Misc Bugs
%   error message for NaN Decimation results

%   FEB 6, 2005
%   optimised k selection

%   DEC 23, 2004
%   Update (c)

%   Dec 15, 2004
%   Handles original fs
%   multiple of 125 Hz

%   Nov 11, 2004
%   Fixed R init

%   Nov 3, 2004
%   Corrected decimation
%   problem of new fs < 100

%   Oct 26, 2004
%   Fixed bug in calculating rem
%   Fixed bug when non-int fs used

if nargin < 3 || isempty(verbose), verbose = true; end

% function Peaks=fmrib_qrsdetect(EEG,ecgchan)

% nargchk(2,2,nargin);
dLFlag=1;

% if ~exist('decimate')
%     error('QRS detection requires the DSP toolbox');
% end

% ofs=EEG.srate;

ofs=fs; % just pass the correct arguments..

% [datachans dummy]=size(EEG.data);
% if ecgchan>datachans | ecgchan<1
%     error('ECG channel out of data range','fmrib_qrsdetect() error!');
% end
% ECG=double(EEG.data(ecgchan,:));
ECG=double(ecg); % also here, pass the correct argugments.. but typecast it anyway.

if rem(ofs,128)==0
    dL=ofs/128;    
elseif rem(ofs,100)==0
    dL=ofs/100;
elseif rem(ofs,125)==0
    dL=ofs/125;  
else
    dL=round(ofs/100);
    if ofs/dL < 100
        dLFlag=0;
        dL=1;
    end
end


%Decimate signal
%---------------
if dLFlag
    if dL>4
        if rem(dL,2)==0
            
            % why like this? -- this is for a 1000 Hz signal.
            Ecg=decimate(ECG,dL/2);
            Ecg=decimate(Ecg,2);
        elseif rem(dL,3)==0
            Ecg=decimate(ECG,dL/3);
            Ecg=decimate(Ecg,3);
        elseif rem(dL,5)==0
            Ecg=decimate(ECG,dL/5);
            Ecg=decimate(Ecg,5);
        elseif rem(dL,7)==0
            Ecg=decimate(ECG,dL/7);
            Ecg=decimate(Ecg,7);
        elseif rem(dL,9)==0
            Ecg=decimate(ECG,dL/9);
            Ecg=decimate(Ecg,9);
        else
            try 
                Ecg=decimate(ECG,dL);
            catch
                Ecg=ECG;
                dL=1;
                dLFlag=0;
            end
        end
    else
        Ecg=decimate(ECG,dL);
    end
else
    Ecg=ECG;
end
fs=ofs/dL;
if find(isnan(Ecg)==1)
    error('Decimation failed.  Downsample the data first and try again');
end



%MFR Settings and init
%----------------------
L=length(Ecg);
msWait=floor(0.55*fs);
ms1200=floor(1.2*fs);
ms350=floor(0.35*fs);
ms300=floor(0.3*fs);
ms50=floor(0.05*fs);
Mc=0.45;
s5=floor(5*fs);
DetectFlag=0;
timer1=0;
Peaks=[];
peakc=1;
firstdetect=1;
Ecg=Ecg(:);

%Allocate memory
%---------------
M=zeros(L,1);
R=zeros(L,1);
F=zeros(L,1);
MFR=zeros(L,1);
Y=zeros(L,1);
M5=ones(5,1);
R5=ones(5,1);
F350=zeros(ms350,1);

%Pre-proc Filtering
%-----------------
fL=round(fs/50);

if fL > 1,
    b=ones(1,fL)/fL;
Ecg=filtfilt(b,1,double(Ecg));
end
fL=round(fs/35);
if fL > 1,
b=ones(1,fL)/fL;
Ecg=filtfilt(b,1,double(Ecg));
end

%Estimate init R and k
%-----------------
FFTp=round(100*fs);
P2=ceil(log(FFTp)/log(2));
NFFT=2^P2;
Fecg=fft(detrend(Ecg(1:round(5*fs))).*hann(length(Ecg(1:round(5*fs)))),NFFT);
Pecg=Fecg.*conj(Fecg) / NFFT;
[MV,ML]=max(Pecg);
R5=R5*round(NFFT/ML);
k= round(fs*fs*pi/(2*2*pi*10*(R5(1))));


%Construct complex lead Y using TEO
%----------------------------------
f=[0 7/(fs/2) 9/(fs/2) 40/(fs/2) 42/(fs/2) 1];
a=[0 0 1 1 0 0];
wts=firls(100,f,a);
ecgF=Ecg;
ecgF=filtfilt(wts,1,double(Ecg));
for n=(k+1):(L-k)
    Y(n)=ecgF(n)^2-ecgF(n-k)*ecgF(n+k);
end
Y(L)=0;
fL=round(fs/25);
b=ones(1,fL)/fL;
Y=filtfilt(b,1,double(Y));
Y(find(Y<0))=0;


%init M and F
%-------------
M5=Mc*max(Y(round(fs):round(fs+s5)))*M5;
M(1:s5)=mean(M5);
newM5=mean(M5);
F(1:ms350)=mean(Y(fs:fs+ms350));
F2(1:ms350)=F(1:ms350);

%Detect QRS
%----------
if verbose, 
    Lby100 = floor(L/100);
    tinit = tic; 
end

for n=1:L
    
    %wait bar
    if n==1
        barth=5;
        barth_step=barth;
        Flag25=0;
        Flag50=0;
        Flag75=0;
        if verbose > 2,
            fprintf('\nStage 1 of 5: Adaptive threshold peak detection.\n');
        end
    end
   
    %-----------------calc------------------------------------------

    timer1=timer1+1;
        
	if length(Peaks)>=2
        if DetectFlag==1
            DetectFlag=0;   
            M(n)=mean(M5);
            Mdec=(M(n)-M(n)*Mc)/(ms1200-msWait);
            Rdec=Mdec/1.4;
        elseif DetectFlag==0 & (timer1<=msWait | timer1 > ms1200)
            M(n)=M(n-1);
        elseif DetectFlag==0 & timer1 == msWait+1
            M(n)=M(n-1)-Mdec;
            newM5=Mc*max(Y(n-msWait:n));
            if newM5 > 1.5*M5(5)
                newM5=1.5*M5(5);
            end
            M5=[M5(2:end);newM5];
        elseif DetectFlag==0 & timer1 > msWait+1 & timer1 <= ms1200
            M(n)=M(n-1)-Mdec;
        end
    end
    
    if n>ms350
        F(n)=F(n-1)+(max(Y(n-ms50+1:n))-max(Y(n-ms350+1:n-ms300)))/150;
        F2(n)=F(n)-mean(Y(fs:fs+ms350))+newM5;
        %F(n)=mean(Y(n-ms350+1:n))+(max(Y(n-ms50+1:n))-...
         %   max(Y(n-ms350+1:n-ms300)))/150;
%          Me(n)=mean(Y(n-ms350+1:n));
%          Fl(n)=max(Y(n-ms50+1:n));
%          Fe(n)=max(Y(n-ms350+1:n-ms300));
    end            
    
    Rm=mean(R5);
    R0int=round(2*Rm/3);
    if timer1 <= R0int
        R(n)=0;
    elseif length(Peaks) >=2
        R(n)=R(n-1)-Rdec;
    end
        
    MFR(n)=M(n)+F2(n)+R(n);
    
        
    if (Y(n)>=MFR(n) & timer1 >msWait) | (Y(n)>=MFR & firstdetect==1)
        if firstdetect==1;
            firstdetect=0;
        end
        Peaks(peakc)=n;
        if peakc>1
            R5=[R5(2:end);Peaks(peakc)-Peaks(peakc-1)];
        end
        peakc=peakc+1;
        DetectFlag=1;
        timer1=-1;
    end
    
    %---------------------------------------------------------------
    %update wait bar
    percentdone=floor(n*100/L);
    if floor(percentdone)>=barth
        if percentdone>=25 & Flag25==0
            if verbose > 2, fprintf('25%% '); end
            Flag25=1;
        elseif percentdone>=50 & Flag50==0
            if verbose > 2, fprintf('50%% '); end
            Flag50=1;
        elseif percentdone>=75 & Flag75==0
            if verbose > 2, fprintf('75%% '); end
            Flag75=1;
        elseif percentdone==100
            if verbose > 2, fprintf('100%%\n'); end
        elseif verbose > 2,
            fprintf('.')
        end

        while barth<=percentdone
            barth=barth+barth_step;
        end
        if barth>100
            barth=100;
        end
    end 
    
    if verbose > 0 && ~mod(n, Lby100),
       misc.eta(tinit, L, n); 
    end
end

%correct QRS Peaks
%-----------------
%Peaks=qrscorrect(Peaks,Ecg,fs, verbose);
% Peaks=sef.qrscorrect(Peaks,Ecg,fs);
Peaks=Peaks*dL;

% try to obtain a somewhat better alignment!!
% maybe not so useful of your downsampling factor is 1 or 2. Somewhat
% arbitrary what you take a a threshold.
%if dL > 1
%    Peaks=qrsbetteralign(Peaks,ECG,fs*dL, verbose);
%end

% insert bcg where possible + further cleanup...
%[Peaks Correlations]=qrs_postprocessing(Peaks,ECG,fs*dL, verbose);

% and now find the pieces that have 0 in them; expand them with 0.5*median.


% cluster them to find regions without good bcg artifact that we will try
% to process a second time.



% processing a second time: a final effort to insert heartbeats in stuff where usabledata =
% 0.




return;
