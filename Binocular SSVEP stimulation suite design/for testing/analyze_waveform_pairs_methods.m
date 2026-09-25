
% =========================================================================
% analyze_waveform_pairs_methods.m
% Offline analysis for generate_waveform_pairs_demo.m
%
% Step 1: Plots the raw luminance PULSE PATTERNS for all 3 waveforms
%         (Triangle, Square, Sine), separately for the left eye and the
%         right eye, using one representative trial.
%
% Step 2: Computes the ACTUAL achieved flicker frequency of all 6 circles
%         using FOUR independent methods (Hilbert and Goertzel excluded):
%   1) FFT magnitude-spectrum peak
%   2) Zero-crossing rate (sub-sample linear interpolation)
%   3) Autocorrelation peak-lag
%   4) Direct frame-timing method (TRULY independent this time - see below)
%
% IMPORTANT FIX vs. the earlier dual-target script: previously "Direct
% Frame Timing" was mistakenly just a copy of the Zero-Crossing result.
% Here it is computed independently, using ONLY the real inter-frame
% timing statistics (never looking at the luminance values at all):
%
%   frameRate_thisTrial = 1 / mean(diff(raw flip timestamps))
%   f_achieved = f_nominal * (frameRate_thisTrial / MeasuredHz_atSetup)
%
% This captures drift/mismatch between the refresh rate measured at
% experiment setup and the refresh rate actually sustained during a
% given trial, independently of the displayed waveform's shape.
% =========================================================================

clear; close all;

F  = readtable('waveform_pairs_flickerlog.csv');
T  = readtable('waveform_pairs_events.tsv', 'FileType','text', 'Delimiter','\t');
M  = readtable('waveform_pairs_metadata.csv');

measuredHz_atSetup = M.MeasuredHz_atSetup(1);
nominalHz          = M.NominalHz(1);
leftFreq  = M.LeftFreq_Hz(1);
rightFreq = M.RightFreq_Hz(1);
leftPhase  = M.LeftPhase_pi(1);
rightPhase = M.RightPhase_pi(1);
nominalPhase = [leftPhase, leftPhase, leftPhase, rightPhase, rightPhase, rightPhase];

fprintf('Screen refresh rate measured at setup: %.4f Hz\n', measuredHz_atSetup);
fprintf('OS-reported nominal refresh rate: %.4f Hz\n', nominalHz);

circleNames  = {'TriL','SqL','SineL','TriR','SqR','SineR'};
waveNames    = {'Triangle','Square','Sine','Triangle','Square','Sine'};
eyeNames     = {'Left','Left','Left','Right','Right','Right'};
nominalFreq  = [leftFreq, leftFreq, leftFreq, rightFreq, rightFreq, rightFreq];

fs_fft    = 1000;
minFreqHz = 2; maxFreqHz = 40;
trialToPlot = 1;

trials  = unique(F.Trial);
nTrials = length(trials);
methodNames = {'FFT','ZeroCrossing','Autocorrelation','DirectFrameTiming'};
results = nan(nTrials, 6, 4);   % trial x circle x method

% ================== STEP 1: PLOT RAW PULSE PATTERNS (per eye) ==================
sub = F(F.Trial == trialToPlot, :);
t = sub.Timestamp_s - sub.Timestamp_s(1);

fig0 = figure('Position',[50 50 1400 650]);
for ci = 1:6
    subplot(2,3,ci);
    plot(t, sub.(circleNames{ci}), 'LineWidth', 1.3);
    title(sprintf('%s eye - %s (%.2f Hz, %.2f \x03C0)', ...
        eyeNames{ci}, waveNames{ci}, nominalFreq(ci), nominalPhase(ci)));
    xlabel('Time (s)'); ylabel('Luminance (0-255)');
    ylim([-10 265]);
    grid on;
end
sgtitle(sprintf('Raw Pulse Patterns per Eye and Waveform Type (Trial %d)', trialToPlot));
saveas(fig0, 'waveform_pulse_patterns.png');

% ================== STEP 2: COMPUTE ALL 4 FREQUENCY METHODS ==================
for ti = 1:nTrials
    trNum = trials(ti);
    subT = F(F.Trial == trNum, :);
    tsAbs = subT.Timestamp_s;
    tReal = tsAbs - tsAbs(1);

    % Method 4 ingredient: real frame rate sustained during THIS trial,
    % computed purely from inter-frame timing (no luminance values used)
    frameRate_thisTrial = 1 / mean(diff(tsAbs));

    for ci = 1:6
        sigRaw = subT.(circleNames{ci});
        sig = sigRaw - mean(sigRaw);
        fq = nominalFreq(ci);

        % ---- Method 1: FFT peak ----
        tUniform = 0:1/fs_fft:tReal(end);
        sigUniform = interp1(tReal, sig, tUniform, 'linear', 'extrap');
        N = length(sigUniform);
        Y = abs(fft(sigUniform));
        freqAxis = (0:N-1) * (fs_fft/N);
        halfN = floor(N/2);
        validBins = freqAxis(1:halfN) >= minFreqHz & freqAxis(1:halfN) <= maxFreqHz;
        idxValid = find(validBins);
        [~, pk] = max(Y(idxValid));
        fftFreq = freqAxis(idxValid(pk));
        results(ti, ci, 1) = fftFreq;

        % ---- Method 2: Zero-crossing rate ----
        signChange = find(diff(sign(sig)) > 0);
        crossTimes = zeros(size(signChange));
        for k = 1:length(signChange)
            i1 = signChange(k); i2 = i1+1;
            frac = -sig(i1) / (sig(i2)-sig(i1));
            crossTimes(k) = tReal(i1) + frac*(tReal(i2)-tReal(i1));
        end
        if length(crossTimes) >= 2
            zcFreq = 1/mean(diff(crossTimes));
        else
            zcFreq = NaN;
        end
        results(ti, ci, 2) = zcFreq;

        % ---- Method 3: Autocorrelation peak lag ----
        sigAC = interp1(tReal, sig, tUniform, 'linear', 'extrap');
        [acf, lags] = xcorr(sigAC, 'coeff');
        acf = acf(lags >= 0); lags = lags(lags >= 0);
        minLagSamples = round(fs_fft/maxFreqHz);
        maxLagSamples = min(round(fs_fft/minFreqHz), length(acf)-1);
        searchRange = minLagSamples:maxLagSamples;
        [~, pkLag] = max(acf(searchRange+1));
        bestLagSamples = searchRange(pkLag);
        acFreq = fs_fft / bestLagSamples;
        results(ti, ci, 3) = acFreq;

        % ---- Method 4: Direct frame-timing (TRULY independent) ----
        % Uses ONLY frame-rate statistics, never the luminance signal itself.
        directFreq = fq * (frameRate_thisTrial / measuredHz_atSetup);
        results(ti, ci, 4) = directFreq;
    end
end

% ================== SUMMARY TABLE (mean +/- std across trials) ==================
meanResults = squeeze(mean(results, 1, 'omitnan'));
stdResults  = squeeze(std(results, 0, 1, 'omitnan'));

summaryT = table();
for ci = 1:6
    fftStr    = sprintf('%.3f \x00B1 %.3f', meanResults(ci,1), stdResults(ci,1));
    zcStr     = sprintf('%.3f \x00B1 %.3f', meanResults(ci,2), stdResults(ci,2));
    acStr     = sprintf('%.3f \x00B1 %.3f', meanResults(ci,3), stdResults(ci,3));
    directStr = sprintf('%.3f \x00B1 %.3f', meanResults(ci,4), stdResults(ci,4));

row = table({circleNames{ci}}, {eyeNames{ci}}, {waveNames{ci}}, nominalFreq(ci), ...
    {fftStr}, {zcStr}, {acStr}, {directStr}, ...
    'VariableNames', {'Circle','Eye','Waveform','Nominal_Hz', ...
        'FFT_Mean_pm_Std','ZeroCross_Mean_pm_Std','Autocorr_Mean_pm_Std','DirectFrameTiming_Mean_pm_Std'});
summaryT = [summaryT; row];
end

writetable(summaryT, 'waveform_pairs_frequency_methods_summary.csv');
disp(summaryT);

xLabels = strcat(eyeNames, {' - '}, waveNames);

% ================== VISUALIZATION: TRIAL-BY-TRIAL STABILITY PER METHOD ==================
fig2 = figure();
colors = lines(6);
for m = 1:4
    subplot(2,2,m);
    hold on;
    for ci = 1:6
        plot(trials, results(:,ci,m), '-o', 'Color', colors(ci,:), ...
            'MarkerFaceColor', colors(ci,:), 'LineWidth', 1.2, 'MarkerSize', 4);
    end
    xlabel('Trial'); ylabel('Frequency (Hz)');
    title(methodNames{m});
    legend(xLabels, 'Location', 'best', 'FontSize', 7);
    grid on;
    hold off;
end
sgtitle('Trial-by-Trial Frequency Estimates per Method');
saveas(fig2, 'waveform_frequency_trial_stability.png');