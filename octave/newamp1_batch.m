% newamp1_batch.m
%
% Copyright David Rowe 2016
% This program is distributed under the terms of the GNU General Public License 
% Version 2
%
% Octave script to batch process model parameters using the new
% amplitude model.  Used for generating samples we can listen to.
%
% Usage:
%   ~/codec2-dev/build_linux/src$ ./c2sim ../../raw/hts1a.raw --dump hts1a
%   $ cd ~/codec2-dev/octave
%   octave:14> newamp1_batch("../build_linux/src/hts1a")
%   ~/codec2-dev/build_linux/src$ ./c2sim ../../raw/hts1a.raw --amread hts1a_am.out -o - | play -t raw -r 8000 -s -2 -
% Or with a little more processing:
%   codec2-dev/build_linux/src$ ./c2sim ../../raw/hts2a.raw --amread hts2a_am.out --awread hts2a_aw.out --phase0 --postfilter --Woread hts2a_Wo.out -o - | play -q -t raw -r 8000 -s -2 -

% process a whole file and write results
% TODO: 
%   [ ] refactor decimate-in-time to avoid extra to/from model conversions
%   [ ] switches to turn on/off quantisation
%   [ ] rename mask_sample_freqs, do we need "mask" any more

#{
    [ ] refactor
#}

% In general, this function processes a bunch of amplitudes, we then
% use c2sim to hear the results

function surface = newamp1_batch(samname, optional_Am_out_name, optional_Aw_out_name)
  newamp;
  more off;

  max_amp = 80;
  postfilter = 0;
  synth_phase = 1;

  model_name = strcat(samname,"_model.txt");
  model = load(model_name);
  [frames nc] = size(model);

  voicing_name = strcat(samname,"_pitche.txt");
  voicing = zeros(1,frames);
  
  if exist(voicing_name, "file") == 2
    pitche = load(voicing_name);
    voicing = pitche(:, 3);
  end

  % Choose experiment to run test here -----------------------

  %model_ = experiment_filter(model);
  %model_ = experiment_filter_dec_filter(model);

  %[model_ surface] = experiment_mel_freq(model, 1, 1, voicing);
  %model_ = experiment_dec_abys(model, 8, 1, 1, 1, voicing);
  [model_ voicing_] = experiment_rate_K_dec(model, voicing);

  %model_ = experiment_dec_linear(model_);
  %model_ = experiment_energy_rate_linear(model, 1, 0);

  %[model_ surface] = experiment_mel_diff_freq(model, 0);
  %[model_ rate_K_surface] = experiment_closed_loop_mean(model);

  % ----------------------------------------------------

  if nargin == 2
    Am_out_name = optional_Am_out_name;
  else
    Am_out_name = sprintf("%s_am.out", samname);
  end

  fam  = fopen(Am_out_name,"wb"); 

  Wo_out_name = sprintf("%s_Wo.out", samname);
  fWo  = fopen(Wo_out_name,"wb"); 
  
  if synth_phase
    Aw_out_name = sprintf("%s_aw.out", samname);
    faw = fopen(Aw_out_name,"wb"); 
  end

  for f=1:frames
    printf("%d ", f);   
    Wo = model_(f,1);
    L = min([model_(f,2) max_amp-1]);
    Am = model_(f,3:(L+2));

    Am_ = zeros(1,max_amp);
    Am_(2:L) = Am(1:L-1);

    % optional post filter on linear {Am}, boosts higher amplitudes more than lower,
    % improving shape of formants and reducing muffling.  Note energy
    % normalisation

    if postfilter
      e1 = sum(Am_(2:L).^2);
      Am_(2:L) = Am_(2:L) .^ 1.5;         
      e2 = sum(Am_(2:L).^2);
      Am_(2:L) *= sqrt(e1/e2);
    end

    fwrite(fam, Am_, "float32");
    fwrite(fWo, Wo, "float32");

    if synth_phase

      % synthesis phase spectra from magnitiude spectra using minimum phase techniques

      fft_enc = 512;
      phase = determine_phase(model_, f);
      assert(length(phase) == fft_enc);
      Aw = zeros(1, fft_enc*2); 
      Aw(1:2:fft_enc*2) = cos(phase);
      Aw(2:2:fft_enc*2) = -sin(phase);
      fwrite(faw, Aw, "float32");    
    end
  end
 
  fclose(fam);
  fclose(fWo);
  if synth_phase
    fclose(faw);
  end

  % save voicing file
  
  if exist("voicing_", "var")
    v_out_name = sprintf("%s_v.txt", samname);
    fv  = fopen(v_out_name,"wt"); 
    for f=1:length(voicing_)
      fprintf(fv,"%d\n", voicing_(f));
    end
    fclose(fv);
  end

  printf("\n")

endfunction
 

% experiment to resample freq axis on mel scale, then optionally vq

function [model_ rate_K_surface] = experiment_mel_freq(model, vq_en=0, plots=1, voicing)
  [frames nc] = size(model);
  K = 20; 
  [rate_K_surface rate_K_sample_freqs_kHz] = resample_const_rate_f_mel(model, K);
  
  if plots
    figure(1); clf; mesh(rate_K_surface);
    figure(2); clf; plot_dft_surface(rate_K_surface)
  end

  for f=1:frames
    mean_f(f) = mean(rate_K_surface(f,:));
    rate_K_surface_no_mean(f,:) = rate_K_surface(f,:) - mean_f(f);
  end

  if vq_en
    melvq;
    load train_120_vq; m=5;
       
    [res rate_K_surface_ ind] = mbest(train_120_vq, rate_K_surface_no_mean, m);

    for f=1:frames
        rate_K_surface_(f,:) = post_filter(rate_K_surface_(f,:), 1.5, voicing(f));
    end

    for f=1:frames
      rate_K_surface_(f,:) += mean_f(f);
    end

    rate_K_surface = rate_K_surface_;
  end

  model_ = resample_rate_L(model, rate_K_surface, rate_K_sample_freqs_kHz);

  if plots
    figure(3); clf; mesh(rate_K_surface_no_mean);
    figure(4); clf; plot_dft_surface(rate_K_surface)
  end

  for f=1:frames
    rate_K_surface(f,:) -= mean(rate_K_surface(f,:));
  end
endfunction


% mel spaced sampling, differential in time VQ.  Curiously, couldn't
% get very good results out of this, I suspect a bug

function [model_ rate_K_surface_diff] = experiment_mel_diff_freq(model, vq_en=0)
  [frames nc] = size(model);
  K = 20; 
  [rate_K_surface rate_K_sample_freqs_kHz] = resample_const_rate_f_mel(model, K);
  
  if vq_en
    melvq;
    load surface_diff_vq; m=5;
  end

  for f=1:frames
    mean_f(f,:) = mean(rate_K_surface(f,:));
    rate_K_surface_no_mean(f,:) = rate_K_surface(f,:) - mean_f(f,:);
  end

  rate_K_surface_no_mean_ = zeros(frames, K);
  rate_K_surface_no_mean_diff = zeros(frames, K);
  rate_K_surface_(1,:) = rate_K_surface_diff(1,:) = zeros(1, K);

  for f=2:frames
    rate_K_surface_diff(f,:) = rate_K_surface_no_mean(f,:) - 0.8*rate_K_surface_no_mean_(f-1,:);
    if vq_en
      [res arate_K_surface_diff_ ind] = mbest(surface_diff_vq, rate_K_surface_diff(f,:), m);
      rate_K_surface_diff_(f,:) = arate_K_surface_diff_;
    else
      rate_K_surface_diff_(f,:) = rate_K_surface_diff(f,:);
    end
    rate_K_surface_no_mean_(f,:) = 0.8*rate_K_surface_no_mean_(f-1,:) + rate_K_surface_diff_(f,:);
  end
  
  for f=1:frames
    rate_K_surface_(f,:) = rate_K_surface_no_mean_(f,:) + mean_f(f,:);
  end

  model_ = resample_rate_L(model, rate_K_surface_, rate_K_sample_freqs_kHz);

endfunction


% try vq with open and closed loop mean removal, turns out they give
% identical results lol

function [model_ rate_K_surface] = experiment_closed_loop_mean(model)
  [frames nc] = size(model);
  K = 15; 
  mel_start = ftomel(300); mel_end = ftomel(3000); 
  step = (mel_end-mel_start)/(K-1);
  mel = mel_start:step:mel_end;
  rate_K_sample_freqs_Hz = 700*((10 .^ (mel/2595)) - 1);
  rate_K_sample_freqs_kHz = rate_K_sample_freqs_Hz/1000;

  rate_K_surface = resample_const_rate_f(model, rate_K_sample_freqs_kHz);
  
  load surface_vq; m=1;
   
  for f=1:frames
    amean = mean(rate_K_surface(f,:));
    rate_K_target_no_mean = rate_K_surface(f,:) - amean;
    mse_open_loop(f) = search_vq2(surface_vq(:,:,1), rate_K_target_no_mean, m, 0);
    mse_closed_loop(f) = search_vq2(surface_vq(:,:,1), rate_K_surface(f,:), m, 1);
  end

  printf("rms open loop..: %f\nrms closed loop: %f\n", sqrt(mean(mse_open_loop)), sqrt(mean(mse_closed_loop)));

  % just return model_ as we have to so nothing breaks, it's not actually useful

  model_ = resample_rate_L(model, rate_K_surface, rate_K_sample_freqs_kHz);
    
endfunction


% Experiment with 10ms update rate for energy but 40ms update for spectrum,
% using linear interpolation for spectrum.

function model_c = experiment_energy_rate_linear(model, vq_en, plot_en)
  max_amp = 80;
  [frames nc] = size(model);

  % 10ms mel freq modelling and VQ

  model_ = experiment_mel_freq(model, vq_en, plot_en);

  % Remove energy.  Hmmmm, this is done on Ams rather than surface but that's
  % similar I guess

  e = zeros(1,frames);
  model_a = zeros(frames,max_amp+3);
  for f=1:frames
    L = min([model_(f,2) max_amp-1]);
    Am_ = model_(f,3:(L+2));
    AmdB_ = 20*log10(Am_);
    mean_f(f) = mean(AmdB_);
    AmdB_ -= mean_f(f);
    model_a(f,1) = model_(f,1); model_a(f,2) = L; model_a(f,3:(L+2)) = 10 .^ (AmdB_(1:L)/20);
  end

  % linear interp after removing energy (mean AmdB)

  model_b = experiment_dec_linear(model_a);

  % add back in energy

  model_c = zeros(frames,max_amp+3);
  for f=1:frames
    L = min([model_b(f,2) max_amp-1]);
    Am_ = model_b(f,3:(L+2));
    AmdB_ = 20*log10(Am_);
    AmdB_ += mean_f(f);
    model_c(f,1) = model_b(f,1); model_c(f,2) = L; model_c(f,3:(L+2)) = 10 .^ (AmdB_(1:L)/20);
  end

endfunction


% conventional decimation in time without any filtering, then linear
% interpolation.  Linear interpolation is a two-tap (weak) form of fir
% filtering that may have problems with signals with high freq
% components, for example after quantisation noise is added.  Need to
% look into this some more.
 
function model_ = experiment_dec_linear(model)
  newamp;
  max_amp = 80;

  [frames nc] = size(model);
  model_ = zeros(frames, max_amp+3);
  decimate = 4;
  for f=1:frames    
    AmdB_ = decimate_frame_rate(model, decimate, f, frames);
    L = length(AmdB_);
    model_(f,1) = model(f,1); model_(f,2) = L; model_(f,3:(L+2)) = 10 .^ (AmdB_(1:L)/20);
  end
endfunction


% Linear decimator/interpolator that operates at rate K, includes VQ, post filter, and Wo/E
% quantisation.  Evevoled from abys decimator below.
 
function [model_ voicing_ ] = experiment_rate_K_dec(model, voicing)
  max_amp = 80;
  [frames nc] = size(model);
  model_ = zeros(frames, max_amp+3);
  
  M = 8;
 
  % create frames x K surface.  TODO make all of this operate frame by
  % frame, or at least M/2=4 frames rather than one big chunk

  K = 20; 
  [surface sample_freqs_kHz] = resample_const_rate_f_mel(model, K);
  target_surface = surface;

  % VQ rate K surface.  TODO: If we are decimating by M/2=4 we really
  % only need to do this every 4th frame.

  melvq;
  load train_120_vq; m=5;
       
  for f=1:frames
    mean_f(f) = mean(surface(f,:));
    surface_no_mean(f,:) = surface(f,:) - mean_f(f);
  end

  [res surface_no_mean_ ind] = mbest(train_120_vq, surface_no_mean, m);

  for f=1:frames
    surface_no_mean_(f,:) = post_filter(surface_no_mean_(f,:), sample_freqs_kHz, 1.5);
  end
    
  surface_ = zeros(frames, K);
  for f=1:frames
    surface_(f,:) = surface_no_mean_(f,:) + mean_f(f);
  end

  % break into segments of M frames.  We have 3 samples in M frame
  % segment spaced M/2 apart and interpolate the rest.  This evolved
  % from AbyS scheme below but could be simplified to simple linear
  % interpolation, or using 3 or 4 points but shift of M/2=4 frames.

  interpolated_surface_ = zeros(frames, K);
  for f=1:M:frames-M
    left_vec = surface_(f,:);
    m = f+M/2;
    centre_vec = surface_(m,:);
    right_vec = surface_(f+M,:);
    sample_points = [f m f+M];
    resample_points = f:f+M-1;
    for k=1:K
      interpolated_surface_(resample_points,k) = interp1(sample_points, [left_vec(k) centre_vec(k) right_vec(k)], resample_points, "spline", 0);
    end    
  end

  % break into M/2 segments for purposes of Wo interpolation

  voicing_ = zeros(1, frames);
  for f=1:M/2:frames-M/2

    if !voicing(f) && !voicing(f+M/2)
       model_(f:f+M/2-1,1) = 2*pi/100;
    end

    if voicing(f) && !voicing(f+M/2)
       model_(f:f+M/4-1,1) = model(f,1);
       model_(f+M/4:f+M/2-1,1) = 2*pi/100;
       voicing_(f:f+M/4-1) = 1;
    end

    if !voicing(f) && voicing(f+M/2)
       model_(f:f+M/4-1,1) = 2*pi/100;
       model_(f+M/4:f+M/2-1,1) = model(f+M/2,1);
       voicing_(f+M/4:f+M/2-1) = 1;
    end

    if voicing(f) && voicing(f+M/2)
      Wo_samples = [model(f,1) model(f+M/2,1)];
      model_(f:f+M/2-1,1) = interp1([f f+M/2], Wo_samples, f:f+M/2-1, "linear", 0);
      voicing_(f:f+M/2-1) = 1;
    end

    printf("f: %d f+M/2: %d Wo: %f %f (%f %%) v: %d %d \n", f, f+M/2, model(f,1), model(f+M/2,1), 100*abs(model(f,1) - model_(f+M/2,1))/model(f,1), voicing(f), voicing(f+M/2));
    for i=f:f+M/2-1
      printf("  f: %d v: %d v_: %d Wo: %f Wo_: %f\n", i, voicing(i), voicing_(i), model(i,1),  model_(i,1));
    end
  end
  model_(frames-M/2:frames,1) = pi/100; % set end frames to something sensible

  voicing_ = voicing;
  model_(:,1) = model(:,1);
  %model_(221:225,1) = model(221:225,1);
  %model_(223:224,1) = model(223:224,1);
  model_(:,2) = floor(pi ./ model_(:,1)); % calculate L for each interpolated Wo
  model_ = resample_rate_L(model_, interpolated_surface_, sample_freqs_kHz);

endfunction


% Experimental AbyS decimator that chooses best frames to match
% surface based on AbyS approach.  Can apply post filter at different
% points, and optionally do fixed decimation, at rate K.  Didn't
% produce anything spectacular in AbyS mode, suggest anotehr look with
% some sort of fbf display to see what's going on internally.
 
function model_ = experiment_dec_abys(model, M=8, vq_en=0, pf_en=1, fixed_dec=0, voicing)
  max_amp = 80;
  [frames nc] = size(model);
  model_ = zeros(frames, max_amp+3);

  printf("M: %d vq_en: %d pf_en: %d fixed_dec: %d\n", M, vq_en, pf_en, fixed_dec)

  % create frames x K surface

  K = 20; 
  [surface sample_freqs_kHz] = resample_const_rate_f_mel(model, K);
  target_surface = surface;

  % optionaly VQ surface

  if vq_en
    melvq;
    load train_120_vq; m=5;
       
    for f=1:frames
      mean_f(f) = mean(surface(f,:));
      rate_K_surface_no_mean(f,:) = surface(f,:) - mean_f(f);
    end

    [res rate_K_surface_ ind] = mbest(train_120_vq, rate_K_surface_no_mean, m);

    if pf_en == 1
      for f=1:frames
        rate_K_surface_(f,:) = post_filter(rate_K_surface_(f,:), sample_freqs_kHz, 1.5, voicing(f));
      end
    end
    
    for f=1:frames
      rate_K_surface_(f,:) += mean_f(f);
    end

    surface = rate_K_surface_;
  end

  % break into segments of M frames.  Fix end points, that two of the
  % frames we sample.  Then find best choice in between

  surface_ = zeros(frames, K);
  best_surface_ = zeros(frames, K);

  for f=1:M:frames-M

    left_vec = surface(f,:);
    right_vec = surface(f+M,:);
    resample_points = f:f+M-1;
    best_mse = 1E32;
    best_m = f+1;
    

    if fixed_dec
      m = f+M/2;
      printf("%d %d %d\n", f, m, M+f);
      centre_vec = surface(m,:);
      sample_points = [f m f+M];
      for k=1:K
        best_surface_(resample_points,k)  = interp1(sample_points, [left_vec(k) centre_vec(k) right_vec(k)], resample_points, "spline", 0);
      end 
    else
      printf("%d %d\n", f, M+f);
      for m=f+1:M+f-2

        % Use interpolation to construct candidate surface_ segment 
        % using just threee samples

        centre_vec = surface(m,:);
        sample_points = [f m f+M];
        mse = 0;
        for k=1:K
          surface_(resample_points,k)  = interp1(sample_points, [left_vec(k) centre_vec(k) right_vec(k)], resample_points, "spline", 0);
          mse += sum((target_surface(resample_points,k) - surface_(resample_points,k)).^2);
        end 

        % compare synthesised candidate to orginal and chose min ased on MSE

        if mse < best_mse
          best_mse = mse;
          best_m = m;
          best_surface_(resample_points,:) = surface_(resample_points,:);
        end

        printf("  m: %d mse: %f best_mse: %f best_m: %d\n", m, mse, best_mse, best_m);
      end
    end
  end

  if pf_en == 2

    % Optionally apply pf after interpolation, theory is interpolation
    % smooths spectrum in time so post filtering afterwards may be
    % useful.  Note we remove mean, this tends to move formats up and
    % anti-formants down when we multiply by a constant

    for f=1:frames
      mean_f = mean(best_surface_(f,:));
      rate_K_vec_no_mean = best_surface_(f,:) - mean_f;
      rate_K_vec_no_mean *= 1.2;
      best_surface_(f,:) = rate_K_vec_no_mean + mean_f;
    end
  end

  model_ = resample_rate_L(model, best_surface_, sample_freqs_kHz);
  figure(5);
  plot(mean_f,'+-')
  figure(6)
  hist(mean_f)
endfunction


#{ 
  Filtering time axis or surface, as a first step before decimation.
  So given surface, lets look at spectral content and see if we can
  reduce it while maintaining speech quality.  First step is to dft
  across time and plot.

  This just has one filtering step, which may help quantisation.  In practice
  we may need filtering before decimation and at the inerpolation stage
#}

function model_ =  experiment_filter(model)
  [frames nc] = size(model);
  K = 40; rate_K_sample_freqs_kHz = (1:K)*4/K;
  [rate_K_surface rate_K_sample_freqs_kHz] = resample_const_rate_f(model, rate_K_sample_freqs_kHz);
  
  Nf = 4; Nf2 = 6;
  [b a]= cheby1(4, 1, 0.20);
  %Nf = 20; Nf2 = 10;
  %b = fir1(Nf, 0.25); a = [1 zeros(1, Nf)];
  %Nf = 1; Nf2 = 1;
  %b = 1; a = [1 zeros(1, Nf)];

  %Nf = 2; Nf2 = 1;
  %beta = 0.99; w = pi/4;
  %b = [1 -2*beta*cos(w) beta*beta]; a = [1 zeros(1, Nf)];
  %Nf = 10; Nf2 = 10;
  %b = fir2(10, [0 0.2 0.3 1], [1 1 0.1 0.1]); a = [1 zeros(1, Nf)];

  %Nf = 1; Nf2 = 1;
  dft_surface = zeros(frames,K);
  rate_K_surface_filt = zeros(frames,K);
  dft_surface_filt = zeros(frames,K);
  for k=1:K
    dft_surface(:,k) = fft(rate_K_surface(:,k).*hanning(frames));
    %rate_K_surface_filt(:,k) = filter(b, a, rate_K_surface(:,k));
    rate_K_surface_filt(:,k) = filter(b, a,  rate_K_surface(:,k));
    dft_surface_filt(:,k) = fft(rate_K_surface_filt(:,k).*hanning(frames));
  end
  figure(1); clf;
  mesh(abs(dft_surface))
  figure(2); clf;
  mesh(abs(dft_surface_filt))

  Fs = 100; Ts = 1/Fs;
  figure(3);
  subplot(211);
  h = freqz(b,a,Fs/2);
  plot(1:Fs/2, 20*log10(abs(h)))
  axis([1 Fs/2 -40 0])
  ylabel('Gain (dB)')
  grid;
  subplot(212)
  [g w] = grpdelay(b,a);
  plot(w*Fs/pi, 1000*g*Ts)
  %axis([1 Fs/2 0 0.5])
  xlabel('Frequency (Hz)');
  ylabel('Delay (ms)')
  grid

  figure(4); clf; stem(filter(b,a,[1 zeros(1,20)]))
  
  % adjust for time offset due to filtering

  rate_K_surface_filt = [rate_K_surface_filt(Nf2:frames,:); zeros(Nf2, K)];

  % back down to rate L

  model_ = resample_rate_L(model, rate_K_surface_filt, rate_K_sample_freqs_kHz);
endfunction


% filter, decimate, zero insert, filter, simulates decimation and re-interpolation, as
% an alternative to simple linear interpolation.

function model_ =  experiment_filter_dec_filter(model)
  [frames nc] = size(model);

  % rate K surface

  K = 40; rate_K_sample_freqs_kHz = (1:K)*4/K;
  [rate_K_surface rate_K_sample_freqs_kHz] = resample_const_rate_f(model, rate_K_sample_freqs_kHz);
  
  % filter, not we run across each of the K bins, treating them as a 1-D sequence

  Nf = 4; filter_delay = 12;
  [b a]= cheby1(4, 1, 0.20);
  %Nf = 10; Nf2 = Nf/2; filter_delay = Nf2*2;
  %b = fir1(Nf, 0.25); a = [1 zeros(1, Nf)];
  %Nf = 10; Nf2 = 2; filter_delay = 2*Nf2;
  %b = fir2(10, [0 0.2 0.3 1], [1 1 0.1 0.1]); a = [1 zeros(1, Nf)];

  rate_K_surface_filt = zeros(frames,K);
  for k=1:K
    rate_K_surface_filt(:,k) = filter(b, a, rate_K_surface(:,k));
  end

  % decimate from 100 to 25Hz, and zero pad, which we simulate by
  % setting all K samples in 3 out of 4 time-samples to zero

  M = 4;

  for f=1:frames
    if mod(f,M)
      rate_K_surface_filt(f,:) = zeros(1,K);
    end
  end

  % filter to reconstruct 100 Hz frame rate

  rate_K_surface_filt_recon = zeros(frames,K);
  for k=1:K
    rate_K_surface_filt_recon(:,k) = filter(b, a, M*rate_K_surface_filt(:,k));
  end

  figure(1); clf;
  mesh(rate_K_surface_filt)
  figure(2); clf;
  mesh(rate_K_surface_filt_recon)

  % adjust for time offset due to 2 lots of filtering

  rate_K_surface_filt_recon = [rate_K_surface_filt_recon(filter_delay:frames,:); zeros(filter_delay, K)];

  % back down to rate L

  model_ = resample_rate_L(model, rate_K_surface_filt_recon, rate_K_sample_freqs_kHz);
endfunction


#{
todo: get this working again

function model_ = experiment_piecewise(model)
  % encoder loop ------------------------------------------------------

  fvec_log = []; amps_log = [];

  for f=1:frames
    printf("%d ", f);   
    Wo = model(f,1);
    L = min([model(f,2) max_amp-1]);
    Am = model(f,3:(L+2));
    AmdB = 20*log10(Am);
    e(f) = sum(AmdB)/L;

    % fit model

    [AmdB_ res fvec fvec_ amps] = piecewise_model(AmdB, Wo);
    fvec_log = [fvec_log; fvec];
    amps_log = [amps_log; amps];

    model_(f,1) = Wo; model_(f,2) = L; model_(f,3:(L+2)) = 10 .^ (AmdB(1:L)/20);
  end

  for f=1:frames
    if 0
    if (f > 1) && (e(f) > (e(f-1)+3))
        decimate = 2;
      else
        decimate = 4;
    end
    end
    printf("%d ", decimate);   
    
    AmdB_ = decimate_frame_rate(model_, decimate, f, frames);
    L = length(AmdB_);

    Am_ = zeros(1,max_amp);
    Am_(2:L) = 10 .^ (AmdB_(1:L-1)/20);  % C array doesnt use A[0]
    fwrite(fam, Am_, "float32");
    fwrite(fWo, Wo, "float32");
  end
endfunction

#}





% early test, devised to test rate K<->L changes along frequency axis

function model_ = resample_half_frame_offset(model, rate_K_surface, rate_K_sample_freqs_kHz)
  max_amp = 80;
  [frames col] = size(model);

  % Check distortion by shifting half a frame and returning model for
  % synthesis Hmm how to handle Wo?  Well lets assume it's OK and
  % average it.  If it sounds OK then it must be OK as well and Am
  % interpolation.  If not then will do some more thinking.

  model_ = zeros(frames, max_amp+3);
  for f=1:frames-1
    Wo = (model(f,1) + model(f+1,1))/2;
    L = min(pi/Wo, max_amp-1);
    rate_L_sample_freqs_kHz = (1:L)*Wo*4/pi;
    
    % interpolate at half frame offset

    half = 0.5*rate_K_surface(f,:) + 0.5*rate_K_surface(f+1,:);
    
    % back down to rate L

    AmdB_ = interp1(rate_K_sample_freqs_kHz, half, rate_L_sample_freqs_kHz, "spline", "extrap");

    % todo a way to save all model params ... Am, Wo, L, (v?)  Start with current facility then
    % make it better

    model_(f,1) = Wo; model_(f,2) = L; model_(f,3:(L+2)) = 10 .^ (AmdB_(1:L)/20);
   end
endfunction


% vq search with optional closed loop mean estimation, turns out this gives
% identical results to extracting the mean externally

function [mse_list index_list] = search_vq2(vq, target, m, closed_loop_dc = 0)

  [Nvec order] = size(vq);

  mse = zeros(1, Nvec);

  % find mse for each vector

  for i=1:Nvec
     if closed_loop_dc
       sum(target - vq(i,:))
       g = sum(target - vq(i,:))/order;
       mse(i) = sum((target - vq(i,:) - g) .^2);
     else
       mse(i) = sum((target - vq(i,:)) .^2);
    end
  end

  % sort and keep top m matches

  [mse_list index_list ] = sort(mse);

  mse_list = mse_list(1:m);
  index_list = index_list(1:m);

endfunction

function plot_dft_surface(surface)
  [frames K] = size(surface);

  dft_surface = zeros(frames,K);
  for k=1:K
    dft_surface(:,k) = fft(surface(:,k).*hanning(frames));
  end

  % Set up a meaninful freq axis.  We only need real side. Sample rate
  % (frame rate) Fs=100Hz 

  Fs = 100; dF = Fs/frames;
  mesh(1:K, (1:frames/2)*dF, 20*log10(abs(dft_surface(1:frames/2,:,:))));
endfunction
