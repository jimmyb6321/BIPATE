function [power, freqs] = channelPSD(data, srate, maxWindows)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/18/2026

% Welch power spectrum per channel from evenly spaced 2 s windows (at most maxWindows of them, so long
% recordings stay quick). Epoched data is joined end to end first.

% IN:   data = [nChan x pnts] or [nChan x pnts x trials]
%       srate = sampling rate (Hz)
%       maxWindows = (optional) most 2 s windows used, default 300

% OUT:  power = [nFreq x nChan] power (units^2/Hz)
%       freqs = [nFreq x 1] frequencies (Hz)

arguments
    data {mustBeNumeric}
    srate (1,1) {mustBePositive}
    maxWindows (1,1) {mustBePositive, mustBeInteger} = 300
end

if nargin < 3, maxWindows = 300; end
data = double(reshape(data, size(data, 1), []));
winLen = round(2 * srate);
nWin = floor(size(data, 2) / winLen);
if nWin < 1
    [power, freqs] = pwelch(data', [], [], [], srate);
    return
end
useWin = unique(round(linspace(1, nWin, min(nWin, maxWindows))));
sampleIdx = (useWin - 1) * winLen + (1:winLen)';
[power, freqs] = pwelch(data(:, sampleIdx(:))', hann(winLen), 0, winLen, srate);
end
