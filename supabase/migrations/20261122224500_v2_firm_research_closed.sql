-- Close research on old firms that are already done (2026-11-22, Alex).
-- Old firms (firm_id < 5799) were researched before; v2_job_firms_missing_details (and section_claim)
-- still list them only for small gaps. A research_closed marker per firm (date, reason, who) makes every
-- research hand-out (v2_next_firm, v2_section_claim, v2_research_claim) skip them.
-- Undo one firm: update public.v2_firm_research_closed set reopened_at = now(), reopen_reason = '...' where firm_id = ...;
-- Nothing on the site reads this table, so site data does not change. Current unexpired claims finish normally.

-- 1. Marker table.
create table if not exists public.v2_firm_research_closed (
  firm_id bigint primary key references public.v2_firms(firm_id),
  closed_at timestamptz not null default now(),
  reason text not null,
  closed_by text not null,
  source_list text,
  reopened_at timestamptz,
  reopen_reason text
);
comment on table public.v2_firm_research_closed is
  'Research closed per firm: research hand-outs skip a firm with a row here and reopened_at null. Set reopened_at to undo.';
alter table public.v2_firm_research_closed enable row level security;
revoke all on public.v2_firm_research_closed from public, anon, authenticated;

-- 2. Shared check.
create or replace function public.v2_firm_research_closed(p_firm_id bigint)
returns boolean
language sql
stable
set search_path to 'public'
as $fn$
  select exists (select 1 from public.v2_firm_research_closed c
                  where c.firm_id = p_firm_id and c.reopened_at is null)
$fn$;
comment on function public.v2_firm_research_closed(bigint) is
  'True when research on a firm is closed (row in v2_firm_research_closed, not reopened). Research hand-outs skip closed firms.';
revoke all on function public.v2_firm_research_closed(bigint) from public, anon, authenticated;

-- 3. Markers: old firms listed by missing_details, plus old firms only section youtube would still issue.
insert into public.v2_firm_research_closed (firm_id, closed_at, reason, closed_by, source_list)
select v.firm_id, now(),
       case v.src when 'missing_details' then 'Old firm (id < 5799), already researched; only small gaps left (legal, reviews, youtube, socials, contact). Alex 2026-11-22.' else 'Old firm (id < 5799), already researched; youtube already covered by a youtube link or nothing_found row; section youtube had no current interview. Alex 2026-11-22.' end,
       'db-admin-close-old-firms-20261122', v.src
  from (values
(17, 'youtube_section'),
(23, 'youtube_section'),
(132, 'youtube_section'),
(172, 'youtube_section'),
(186, 'youtube_section'),
(189, 'youtube_section'),
(195, 'youtube_section'),
(199, 'youtube_section'),
(202, 'youtube_section'),
(205, 'youtube_section'),
(213, 'youtube_section'),
(230, 'youtube_section'),
(232, 'youtube_section'),
(233, 'youtube_section'),
(243, 'youtube_section'),
(246, 'missing_details'),
(248, 'youtube_section'),
(249, 'missing_details'),
(255, 'youtube_section'),
(259, 'youtube_section'),
(270, 'youtube_section'),
(275, 'youtube_section'),
(278, 'youtube_section'),
(286, 'missing_details'),
(287, 'youtube_section'),
(296, 'youtube_section'),
(312, 'youtube_section'),
(370, 'youtube_section'),
(371, 'youtube_section'),
(401, 'youtube_section'),
(404, 'youtube_section'),
(405, 'youtube_section'),
(408, 'youtube_section'),
(418, 'youtube_section'),
(420, 'youtube_section'),
(439, 'youtube_section'),
(455, 'youtube_section'),
(459, 'youtube_section'),
(487, 'youtube_section'),
(524, 'youtube_section'),
(533, 'missing_details'),
(537, 'missing_details'),
(553, 'youtube_section'),
(646, 'missing_details'),
(683, 'missing_details'),
(728, 'youtube_section'),
(860, 'youtube_section'),
(882, 'youtube_section'),
(905, 'youtube_section'),
(911, 'missing_details'),
(936, 'missing_details'),
(943, 'youtube_section'),
(1039, 'youtube_section'),
(1063, 'youtube_section'),
(1095, 'youtube_section'),
(1097, 'youtube_section'),
(1122, 'youtube_section'),
(1142, 'youtube_section'),
(1151, 'youtube_section'),
(1156, 'youtube_section'),
(1161, 'missing_details'),
(1163, 'youtube_section'),
(1166, 'youtube_section'),
(1167, 'youtube_section'),
(1170, 'youtube_section'),
(1172, 'youtube_section'),
(1174, 'youtube_section'),
(1197, 'youtube_section'),
(1199, 'youtube_section'),
(1202, 'youtube_section'),
(1210, 'youtube_section'),
(1223, 'youtube_section'),
(1228, 'youtube_section'),
(1234, 'youtube_section'),
(1242, 'youtube_section'),
(1243, 'youtube_section'),
(1245, 'youtube_section'),
(1249, 'youtube_section'),
(1254, 'youtube_section'),
(1256, 'youtube_section'),
(1261, 'youtube_section'),
(1269, 'youtube_section'),
(1278, 'missing_details'),
(1353, 'youtube_section'),
(1354, 'youtube_section'),
(1359, 'youtube_section'),
(1361, 'youtube_section'),
(1366, 'missing_details'),
(1367, 'youtube_section'),
(1371, 'missing_details'),
(1378, 'youtube_section'),
(1379, 'youtube_section'),
(1388, 'youtube_section'),
(1395, 'youtube_section'),
(1398, 'youtube_section'),
(1399, 'youtube_section'),
(1403, 'missing_details'),
(1406, 'youtube_section'),
(1425, 'youtube_section'),
(1430, 'youtube_section'),
(1433, 'missing_details'),
(1435, 'youtube_section'),
(1440, 'missing_details'),
(1443, 'youtube_section'),
(1446, 'missing_details'),
(1466, 'missing_details'),
(1468, 'youtube_section'),
(1472, 'youtube_section'),
(1473, 'youtube_section'),
(1477, 'missing_details'),
(1478, 'youtube_section'),
(1491, 'youtube_section'),
(1496, 'youtube_section'),
(1503, 'youtube_section'),
(1510, 'youtube_section'),
(1513, 'youtube_section'),
(1517, 'youtube_section'),
(1520, 'youtube_section'),
(1524, 'youtube_section'),
(1533, 'youtube_section'),
(1548, 'youtube_section'),
(1549, 'youtube_section'),
(1559, 'youtube_section'),
(1560, 'youtube_section'),
(1563, 'youtube_section'),
(1567, 'youtube_section'),
(1578, 'youtube_section'),
(1582, 'youtube_section'),
(1588, 'youtube_section'),
(1591, 'youtube_section'),
(1596, 'youtube_section'),
(1609, 'youtube_section'),
(1621, 'youtube_section'),
(1625, 'youtube_section'),
(1631, 'youtube_section'),
(1634, 'youtube_section'),
(1638, 'youtube_section'),
(1639, 'youtube_section'),
(1645, 'youtube_section'),
(1648, 'youtube_section'),
(1653, 'youtube_section'),
(1657, 'youtube_section'),
(1661, 'youtube_section'),
(1666, 'youtube_section'),
(1679, 'youtube_section'),
(1692, 'youtube_section'),
(1697, 'youtube_section'),
(1701, 'youtube_section'),
(1704, 'youtube_section'),
(1718, 'youtube_section'),
(1722, 'missing_details'),
(1728, 'missing_details'),
(1732, 'missing_details'),
(1733, 'youtube_section'),
(1736, 'missing_details'),
(1742, 'youtube_section'),
(1743, 'youtube_section'),
(1744, 'missing_details'),
(1745, 'youtube_section'),
(1747, 'missing_details'),
(1749, 'missing_details'),
(1750, 'youtube_section'),
(1759, 'missing_details'),
(1760, 'youtube_section'),
(1761, 'youtube_section'),
(1765, 'youtube_section'),
(1767, 'missing_details'),
(1777, 'missing_details'),
(1782, 'youtube_section'),
(1783, 'youtube_section'),
(1786, 'youtube_section'),
(1790, 'youtube_section'),
(1794, 'youtube_section'),
(1796, 'missing_details'),
(1803, 'missing_details'),
(1808, 'youtube_section'),
(1809, 'youtube_section'),
(1813, 'youtube_section'),
(1818, 'youtube_section'),
(1829, 'youtube_section'),
(1831, 'youtube_section'),
(1849, 'youtube_section'),
(1852, 'youtube_section'),
(1859, 'youtube_section'),
(1861, 'youtube_section'),
(1866, 'youtube_section'),
(1867, 'youtube_section'),
(1874, 'youtube_section'),
(1880, 'youtube_section'),
(1882, 'youtube_section'),
(1886, 'missing_details'),
(1899, 'youtube_section'),
(1910, 'youtube_section'),
(1911, 'youtube_section'),
(1923, 'youtube_section'),
(1924, 'youtube_section'),
(1928, 'youtube_section'),
(1930, 'youtube_section'),
(1944, 'youtube_section'),
(1950, 'youtube_section'),
(1957, 'youtube_section'),
(1969, 'youtube_section'),
(1984, 'missing_details'),
(1992, 'missing_details'),
(1996, 'missing_details'),
(2001, 'youtube_section'),
(2004, 'missing_details'),
(2011, 'youtube_section'),
(2016, 'youtube_section'),
(2024, 'youtube_section'),
(2034, 'missing_details'),
(2038, 'youtube_section'),
(2040, 'youtube_section'),
(2044, 'youtube_section'),
(2051, 'youtube_section'),
(2068, 'youtube_section'),
(2071, 'youtube_section'),
(2085, 'youtube_section'),
(2094, 'missing_details'),
(2097, 'youtube_section'),
(2102, 'youtube_section'),
(2104, 'youtube_section'),
(2115, 'youtube_section'),
(2118, 'youtube_section'),
(2134, 'youtube_section'),
(2150, 'youtube_section'),
(2156, 'youtube_section'),
(2159, 'youtube_section'),
(2166, 'missing_details'),
(2170, 'missing_details'),
(2181, 'youtube_section'),
(2193, 'youtube_section'),
(2200, 'youtube_section'),
(2202, 'missing_details'),
(2206, 'youtube_section'),
(2209, 'youtube_section'),
(2210, 'missing_details'),
(2211, 'missing_details'),
(2218, 'missing_details'),
(2229, 'missing_details'),
(2231, 'youtube_section'),
(2232, 'youtube_section'),
(2234, 'missing_details'),
(2235, 'missing_details'),
(2250, 'youtube_section'),
(2251, 'missing_details'),
(2252, 'missing_details'),
(2258, 'youtube_section'),
(2260, 'missing_details'),
(2261, 'missing_details'),
(2263, 'youtube_section'),
(2266, 'missing_details'),
(2268, 'youtube_section'),
(2277, 'youtube_section'),
(2278, 'youtube_section'),
(2280, 'missing_details'),
(2281, 'youtube_section'),
(2285, 'missing_details'),
(2286, 'youtube_section'),
(2289, 'youtube_section'),
(2291, 'youtube_section'),
(2293, 'missing_details'),
(2295, 'missing_details'),
(2297, 'youtube_section'),
(2299, 'missing_details'),
(2300, 'youtube_section'),
(2305, 'youtube_section'),
(2318, 'missing_details'),
(2334, 'youtube_section'),
(2336, 'youtube_section'),
(2337, 'youtube_section'),
(2341, 'youtube_section'),
(2345, 'youtube_section'),
(2349, 'missing_details'),
(2351, 'youtube_section'),
(2353, 'youtube_section'),
(2357, 'youtube_section'),
(2359, 'youtube_section'),
(2370, 'missing_details'),
(2387, 'missing_details'),
(2388, 'youtube_section'),
(2395, 'missing_details'),
(2407, 'missing_details'),
(2421, 'missing_details'),
(2424, 'youtube_section'),
(2427, 'youtube_section'),
(2430, 'youtube_section'),
(2431, 'youtube_section'),
(2433, 'missing_details'),
(2437, 'missing_details'),
(2441, 'youtube_section'),
(2453, 'youtube_section'),
(2456, 'missing_details'),
(2461, 'youtube_section'),
(2472, 'missing_details'),
(2489, 'youtube_section'),
(2493, 'missing_details'),
(2499, 'missing_details'),
(2503, 'youtube_section'),
(2507, 'youtube_section'),
(2520, 'youtube_section'),
(2522, 'missing_details'),
(2530, 'missing_details'),
(2532, 'youtube_section'),
(2543, 'missing_details'),
(2552, 'youtube_section'),
(2554, 'missing_details'),
(2559, 'missing_details'),
(2564, 'youtube_section'),
(2573, 'youtube_section'),
(2574, 'youtube_section'),
(2579, 'missing_details'),
(2587, 'youtube_section'),
(2588, 'missing_details'),
(2607, 'missing_details'),
(2613, 'youtube_section'),
(2628, 'youtube_section'),
(2633, 'missing_details'),
(2635, 'youtube_section'),
(2643, 'youtube_section'),
(2654, 'youtube_section'),
(2660, 'youtube_section'),
(2667, 'youtube_section'),
(2669, 'youtube_section'),
(2674, 'youtube_section'),
(2683, 'youtube_section'),
(2686, 'missing_details'),
(2688, 'missing_details'),
(2689, 'missing_details'),
(2691, 'youtube_section'),
(2695, 'youtube_section'),
(2698, 'youtube_section'),
(2711, 'missing_details'),
(2716, 'youtube_section'),
(2717, 'missing_details'),
(2727, 'youtube_section'),
(2733, 'youtube_section'),
(2740, 'youtube_section'),
(2743, 'youtube_section'),
(2748, 'youtube_section'),
(2750, 'youtube_section'),
(2757, 'missing_details'),
(2758, 'missing_details'),
(2759, 'youtube_section'),
(2763, 'youtube_section'),
(2771, 'missing_details'),
(2774, 'youtube_section'),
(2776, 'youtube_section'),
(2786, 'youtube_section'),
(2794, 'youtube_section'),
(2798, 'missing_details'),
(2799, 'missing_details'),
(2800, 'missing_details'),
(2803, 'missing_details'),
(2805, 'missing_details'),
(2809, 'youtube_section'),
(2815, 'youtube_section'),
(2821, 'youtube_section'),
(2835, 'missing_details'),
(2838, 'youtube_section'),
(2848, 'youtube_section'),
(2849, 'missing_details'),
(2851, 'youtube_section'),
(2853, 'youtube_section'),
(2856, 'missing_details'),
(2857, 'missing_details'),
(2862, 'youtube_section'),
(2868, 'youtube_section'),
(2870, 'missing_details'),
(2872, 'missing_details'),
(2873, 'missing_details'),
(2875, 'youtube_section'),
(2881, 'missing_details'),
(2883, 'youtube_section'),
(2887, 'missing_details'),
(2893, 'youtube_section'),
(2898, 'missing_details'),
(2900, 'missing_details'),
(2909, 'missing_details'),
(2910, 'missing_details'),
(2919, 'youtube_section'),
(2920, 'youtube_section'),
(2930, 'missing_details'),
(2941, 'missing_details'),
(2942, 'missing_details'),
(2953, 'missing_details'),
(2954, 'missing_details'),
(2960, 'youtube_section'),
(2961, 'youtube_section'),
(2964, 'missing_details'),
(2965, 'youtube_section'),
(2970, 'youtube_section'),
(2975, 'youtube_section'),
(2978, 'youtube_section'),
(2985, 'missing_details'),
(2987, 'missing_details'),
(2988, 'youtube_section'),
(2990, 'youtube_section'),
(2991, 'missing_details'),
(2995, 'youtube_section'),
(2997, 'missing_details'),
(3000, 'missing_details'),
(3004, 'youtube_section'),
(3008, 'missing_details'),
(3010, 'missing_details'),
(3012, 'missing_details'),
(3017, 'youtube_section'),
(3018, 'youtube_section'),
(3021, 'youtube_section'),
(3024, 'missing_details'),
(3025, 'youtube_section'),
(3026, 'youtube_section'),
(3033, 'missing_details'),
(3039, 'missing_details'),
(3040, 'youtube_section'),
(3046, 'missing_details'),
(3050, 'youtube_section'),
(3064, 'youtube_section'),
(3066, 'youtube_section'),
(3069, 'youtube_section'),
(3071, 'missing_details'),
(3086, 'youtube_section'),
(3088, 'missing_details'),
(3089, 'missing_details'),
(3097, 'youtube_section'),
(3101, 'missing_details'),
(3102, 'missing_details'),
(3108, 'missing_details'),
(3113, 'missing_details'),
(3120, 'missing_details'),
(3121, 'youtube_section'),
(3122, 'missing_details'),
(3123, 'missing_details'),
(3124, 'missing_details'),
(3128, 'youtube_section'),
(3131, 'missing_details'),
(3132, 'youtube_section'),
(3133, 'youtube_section'),
(3134, 'missing_details'),
(3135, 'youtube_section'),
(3136, 'missing_details'),
(3142, 'youtube_section'),
(3143, 'missing_details'),
(3145, 'missing_details'),
(3150, 'missing_details'),
(3162, 'missing_details'),
(3163, 'missing_details'),
(3166, 'youtube_section'),
(3178, 'youtube_section'),
(3180, 'youtube_section'),
(3181, 'missing_details'),
(3184, 'missing_details'),
(3193, 'missing_details'),
(3196, 'missing_details'),
(3198, 'youtube_section'),
(3199, 'missing_details'),
(3205, 'missing_details'),
(3207, 'missing_details'),
(3208, 'missing_details'),
(3209, 'missing_details'),
(3210, 'missing_details'),
(3212, 'missing_details'),
(3219, 'missing_details'),
(3220, 'missing_details'),
(3221, 'missing_details'),
(3222, 'missing_details'),
(3224, 'missing_details'),
(3226, 'youtube_section'),
(3227, 'missing_details'),
(3228, 'missing_details'),
(3232, 'missing_details'),
(3241, 'youtube_section'),
(3242, 'missing_details'),
(3243, 'youtube_section'),
(3247, 'youtube_section'),
(3254, 'missing_details'),
(3256, 'missing_details'),
(3258, 'missing_details'),
(3263, 'missing_details'),
(3268, 'missing_details'),
(3273, 'youtube_section'),
(3274, 'youtube_section'),
(3286, 'youtube_section'),
(3287, 'missing_details'),
(3288, 'youtube_section'),
(3295, 'youtube_section'),
(3304, 'youtube_section'),
(3307, 'youtube_section'),
(3308, 'missing_details'),
(3309, 'youtube_section'),
(3321, 'missing_details'),
(3324, 'youtube_section'),
(3336, 'missing_details'),
(3337, 'missing_details'),
(3339, 'youtube_section'),
(3341, 'missing_details'),
(3344, 'youtube_section'),
(3345, 'youtube_section'),
(3346, 'missing_details'),
(3352, 'youtube_section'),
(3353, 'missing_details'),
(3355, 'missing_details'),
(3356, 'missing_details'),
(3357, 'youtube_section'),
(3358, 'youtube_section'),
(3360, 'missing_details'),
(3362, 'youtube_section'),
(3370, 'youtube_section'),
(3371, 'youtube_section'),
(3380, 'missing_details'),
(3382, 'missing_details'),
(3383, 'missing_details'),
(3388, 'missing_details'),
(3395, 'missing_details'),
(3397, 'missing_details'),
(3417, 'youtube_section'),
(3418, 'youtube_section'),
(3429, 'missing_details'),
(3446, 'youtube_section'),
(3450, 'missing_details'),
(3453, 'missing_details'),
(3462, 'youtube_section'),
(3465, 'missing_details'),
(3472, 'youtube_section'),
(3474, 'youtube_section'),
(3476, 'youtube_section'),
(3477, 'youtube_section'),
(3486, 'youtube_section'),
(3495, 'missing_details'),
(3498, 'missing_details'),
(3516, 'missing_details'),
(3520, 'missing_details'),
(3529, 'missing_details'),
(3535, 'missing_details'),
(3537, 'missing_details'),
(3538, 'youtube_section'),
(3544, 'youtube_section'),
(3551, 'missing_details'),
(3554, 'missing_details'),
(3558, 'youtube_section'),
(3564, 'youtube_section'),
(3568, 'youtube_section'),
(3571, 'youtube_section'),
(3575, 'youtube_section'),
(3582, 'missing_details'),
(3583, 'youtube_section'),
(3586, 'youtube_section'),
(3588, 'youtube_section'),
(3590, 'youtube_section'),
(3591, 'missing_details'),
(3600, 'youtube_section'),
(3608, 'missing_details'),
(3613, 'missing_details'),
(3618, 'missing_details'),
(3624, 'youtube_section'),
(3625, 'missing_details'),
(3626, 'youtube_section'),
(3630, 'missing_details'),
(3631, 'youtube_section'),
(3644, 'youtube_section'),
(3645, 'missing_details'),
(3652, 'youtube_section'),
(3653, 'missing_details'),
(3654, 'youtube_section'),
(3659, 'missing_details'),
(3661, 'missing_details'),
(3666, 'missing_details'),
(3667, 'missing_details'),
(3671, 'missing_details'),
(3674, 'missing_details'),
(3675, 'youtube_section'),
(3680, 'missing_details'),
(3685, 'missing_details'),
(3691, 'youtube_section'),
(3696, 'youtube_section'),
(3697, 'missing_details'),
(3701, 'missing_details'),
(3707, 'missing_details'),
(3710, 'missing_details'),
(3712, 'youtube_section'),
(3718, 'missing_details'),
(3722, 'youtube_section'),
(3723, 'missing_details'),
(3725, 'youtube_section'),
(3735, 'missing_details'),
(3742, 'missing_details'),
(3752, 'youtube_section'),
(3753, 'youtube_section'),
(3757, 'missing_details'),
(3759, 'youtube_section'),
(3764, 'youtube_section'),
(3781, 'missing_details'),
(3786, 'youtube_section'),
(3787, 'missing_details'),
(3792, 'missing_details'),
(3796, 'missing_details'),
(3804, 'youtube_section'),
(3807, 'youtube_section'),
(3808, 'youtube_section'),
(3811, 'youtube_section'),
(3813, 'youtube_section'),
(3818, 'missing_details'),
(3821, 'youtube_section'),
(3822, 'youtube_section'),
(3823, 'missing_details'),
(3825, 'youtube_section'),
(3832, 'youtube_section'),
(3834, 'youtube_section'),
(3839, 'youtube_section'),
(3850, 'missing_details'),
(3854, 'youtube_section'),
(3855, 'youtube_section'),
(3860, 'missing_details'),
(3862, 'missing_details'),
(3865, 'missing_details'),
(3871, 'youtube_section'),
(3880, 'youtube_section'),
(3887, 'missing_details'),
(3893, 'youtube_section'),
(3901, 'youtube_section'),
(3907, 'youtube_section'),
(3909, 'missing_details'),
(3911, 'missing_details'),
(3913, 'missing_details'),
(3920, 'missing_details'),
(3925, 'youtube_section'),
(3935, 'youtube_section'),
(3937, 'youtube_section'),
(3940, 'youtube_section'),
(3941, 'youtube_section'),
(3949, 'missing_details'),
(3952, 'youtube_section'),
(3953, 'youtube_section'),
(3955, 'missing_details'),
(3956, 'youtube_section'),
(3957, 'missing_details'),
(3964, 'missing_details'),
(3968, 'missing_details'),
(3974, 'missing_details'),
(3977, 'youtube_section'),
(3987, 'missing_details'),
(3993, 'missing_details'),
(4001, 'youtube_section'),
(4005, 'missing_details'),
(4010, 'youtube_section'),
(4011, 'missing_details'),
(4014, 'youtube_section'),
(4025, 'missing_details'),
(4029, 'missing_details'),
(4033, 'missing_details'),
(4036, 'missing_details'),
(4048, 'missing_details'),
(4049, 'youtube_section'),
(4050, 'youtube_section'),
(4056, 'missing_details'),
(4061, 'missing_details'),
(4062, 'youtube_section'),
(4063, 'youtube_section'),
(4064, 'missing_details'),
(4065, 'missing_details'),
(4066, 'missing_details'),
(4072, 'youtube_section'),
(4083, 'youtube_section'),
(4096, 'missing_details'),
(4098, 'missing_details'),
(4099, 'missing_details'),
(4100, 'missing_details'),
(4102, 'youtube_section'),
(4103, 'missing_details'),
(4108, 'missing_details'),
(4109, 'youtube_section'),
(4111, 'missing_details'),
(4116, 'youtube_section'),
(4117, 'missing_details'),
(4124, 'missing_details'),
(4130, 'youtube_section'),
(4135, 'missing_details'),
(4137, 'missing_details'),
(4138, 'missing_details'),
(4143, 'missing_details'),
(4145, 'youtube_section'),
(4147, 'missing_details'),
(4149, 'missing_details'),
(4153, 'missing_details'),
(4158, 'missing_details'),
(4163, 'missing_details'),
(4165, 'youtube_section'),
(4166, 'missing_details'),
(4167, 'missing_details'),
(4170, 'missing_details'),
(4172, 'youtube_section'),
(4174, 'missing_details'),
(4181, 'youtube_section'),
(4184, 'youtube_section'),
(4188, 'missing_details'),
(4190, 'missing_details'),
(4199, 'missing_details'),
(4200, 'missing_details'),
(4205, 'missing_details'),
(4207, 'missing_details'),
(4218, 'missing_details'),
(4219, 'youtube_section'),
(4224, 'youtube_section'),
(4227, 'youtube_section'),
(4230, 'youtube_section'),
(4253, 'missing_details'),
(4254, 'youtube_section'),
(4256, 'youtube_section'),
(4257, 'missing_details'),
(4260, 'missing_details'),
(4266, 'youtube_section'),
(4269, 'missing_details'),
(4270, 'missing_details'),
(4277, 'missing_details'),
(4278, 'youtube_section'),
(4281, 'youtube_section'),
(4284, 'missing_details'),
(4285, 'missing_details'),
(4293, 'missing_details'),
(4298, 'missing_details'),
(4303, 'missing_details'),
(4304, 'youtube_section'),
(4305, 'youtube_section'),
(4310, 'missing_details'),
(4315, 'youtube_section'),
(4318, 'missing_details'),
(4321, 'missing_details'),
(4323, 'missing_details'),
(4324, 'youtube_section'),
(4330, 'missing_details'),
(4331, 'missing_details'),
(4333, 'missing_details'),
(4334, 'missing_details'),
(4338, 'youtube_section'),
(4342, 'missing_details'),
(4343, 'youtube_section'),
(4344, 'youtube_section'),
(4351, 'youtube_section'),
(4353, 'missing_details'),
(4355, 'youtube_section'),
(4364, 'missing_details'),
(4368, 'missing_details'),
(4370, 'missing_details'),
(4372, 'youtube_section'),
(4376, 'missing_details'),
(4378, 'youtube_section'),
(4382, 'missing_details'),
(4383, 'missing_details'),
(4386, 'missing_details'),
(4405, 'youtube_section'),
(4407, 'missing_details'),
(4412, 'youtube_section'),
(4420, 'youtube_section'),
(4423, 'youtube_section'),
(4425, 'missing_details'),
(4429, 'missing_details'),
(4440, 'missing_details'),
(4448, 'missing_details'),
(4450, 'missing_details'),
(4451, 'youtube_section'),
(4464, 'missing_details'),
(4468, 'youtube_section'),
(4483, 'missing_details'),
(4486, 'missing_details'),
(4501, 'missing_details'),
(4506, 'youtube_section'),
(4507, 'youtube_section'),
(4512, 'missing_details'),
(4513, 'missing_details'),
(4514, 'missing_details'),
(4519, 'youtube_section'),
(4525, 'missing_details'),
(4528, 'missing_details'),
(4530, 'missing_details'),
(4533, 'youtube_section'),
(4537, 'youtube_section'),
(4539, 'youtube_section'),
(4544, 'missing_details'),
(4555, 'youtube_section'),
(4556, 'missing_details'),
(4557, 'youtube_section'),
(4570, 'youtube_section'),
(4572, 'youtube_section'),
(4577, 'missing_details'),
(4579, 'missing_details'),
(4583, 'missing_details'),
(4589, 'youtube_section'),
(4596, 'youtube_section'),
(4598, 'youtube_section'),
(4602, 'missing_details'),
(4606, 'youtube_section'),
(4621, 'youtube_section'),
(4623, 'missing_details'),
(4626, 'missing_details'),
(4629, 'missing_details'),
(4630, 'youtube_section'),
(4632, 'missing_details'),
(4633, 'missing_details'),
(4636, 'missing_details'),
(4644, 'missing_details'),
(4648, 'youtube_section'),
(4649, 'missing_details'),
(4654, 'youtube_section'),
(4655, 'missing_details'),
(4656, 'missing_details'),
(4667, 'missing_details'),
(4684, 'youtube_section'),
(4699, 'missing_details'),
(4705, 'missing_details'),
(4706, 'youtube_section'),
(4707, 'missing_details'),
(4709, 'missing_details'),
(4710, 'missing_details'),
(4716, 'missing_details'),
(4728, 'missing_details'),
(4731, 'youtube_section'),
(4736, 'missing_details'),
(4741, 'missing_details'),
(4743, 'missing_details'),
(4744, 'missing_details'),
(4745, 'missing_details'),
(4746, 'youtube_section'),
(4747, 'missing_details'),
(4753, 'missing_details'),
(4756, 'youtube_section'),
(4767, 'youtube_section'),
(4779, 'missing_details'),
(4784, 'missing_details'),
(4787, 'missing_details'),
(4805, 'youtube_section'),
(4811, 'missing_details'),
(4812, 'missing_details'),
(4822, 'youtube_section'),
(4827, 'missing_details'),
(4830, 'missing_details'),
(4841, 'youtube_section'),
(4851, 'missing_details'),
(4860, 'youtube_section'),
(4863, 'youtube_section'),
(4867, 'youtube_section'),
(4869, 'missing_details'),
(4879, 'missing_details'),
(4887, 'missing_details'),
(4890, 'youtube_section'),
(4895, 'missing_details'),
(4897, 'missing_details'),
(4908, 'missing_details'),
(4922, 'missing_details'),
(4927, 'youtube_section'),
(4928, 'youtube_section'),
(4932, 'missing_details'),
(4935, 'missing_details'),
(4947, 'missing_details'),
(4953, 'missing_details'),
(4954, 'youtube_section'),
(4955, 'youtube_section'),
(4961, 'missing_details'),
(4963, 'youtube_section'),
(4965, 'missing_details'),
(4969, 'youtube_section'),
(4991, 'youtube_section'),
(4998, 'missing_details'),
(4999, 'missing_details'),
(5003, 'missing_details'),
(5005, 'youtube_section'),
(5007, 'youtube_section'),
(5009, 'missing_details'),
(5014, 'missing_details'),
(5015, 'missing_details'),
(5034, 'youtube_section'),
(5038, 'missing_details'),
(5039, 'missing_details'),
(5040, 'missing_details'),
(5041, 'youtube_section'),
(5049, 'missing_details'),
(5050, 'missing_details'),
(5052, 'missing_details'),
(5054, 'youtube_section'),
(5060, 'missing_details'),
(5061, 'missing_details'),
(5067, 'missing_details'),
(5069, 'missing_details'),
(5073, 'youtube_section'),
(5084, 'missing_details'),
(5086, 'youtube_section'),
(5098, 'youtube_section'),
(5103, 'missing_details'),
(5107, 'youtube_section'),
(5120, 'missing_details'),
(5125, 'missing_details'),
(5130, 'youtube_section'),
(5132, 'missing_details'),
(5144, 'youtube_section'),
(5151, 'missing_details'),
(5155, 'youtube_section'),
(5158, 'missing_details'),
(5162, 'youtube_section'),
(5163, 'missing_details'),
(5172, 'youtube_section'),
(5174, 'youtube_section'),
(5178, 'missing_details'),
(5181, 'missing_details'),
(5184, 'youtube_section'),
(5190, 'missing_details'),
(5191, 'missing_details'),
(5194, 'missing_details'),
(5206, 'missing_details'),
(5207, 'missing_details'),
(5213, 'missing_details'),
(5214, 'youtube_section'),
(5217, 'missing_details'),
(5218, 'youtube_section'),
(5222, 'youtube_section'),
(5223, 'youtube_section'),
(5232, 'missing_details'),
(5233, 'missing_details'),
(5235, 'missing_details'),
(5236, 'missing_details'),
(5279, 'missing_details'),
(5280, 'missing_details'),
(5281, 'missing_details'),
(5282, 'missing_details'),
(5283, 'missing_details'),
(5284, 'missing_details'),
(5285, 'missing_details'),
(5286, 'missing_details'),
(5287, 'missing_details'),
(5288, 'missing_details'),
(5289, 'missing_details'),
(5290, 'missing_details'),
(5291, 'missing_details'),
(5292, 'missing_details'),
(5293, 'missing_details'),
(5294, 'missing_details'),
(5295, 'missing_details'),
(5296, 'missing_details'),
(5297, 'missing_details'),
(5298, 'missing_details'),
(5299, 'missing_details'),
(5300, 'missing_details'),
(5301, 'missing_details'),
(5302, 'missing_details'),
(5303, 'missing_details'),
(5304, 'missing_details'),
(5305, 'missing_details'),
(5306, 'missing_details'),
(5307, 'missing_details'),
(5308, 'missing_details'),
(5309, 'missing_details'),
(5310, 'missing_details'),
(5311, 'missing_details'),
(5312, 'missing_details'),
(5313, 'missing_details'),
(5314, 'missing_details'),
(5315, 'missing_details'),
(5316, 'missing_details'),
(5317, 'missing_details'),
(5318, 'missing_details'),
(5319, 'missing_details'),
(5320, 'missing_details'),
(5321, 'missing_details'),
(5322, 'missing_details'),
(5323, 'missing_details'),
(5324, 'missing_details'),
(5325, 'missing_details'),
(5326, 'missing_details'),
(5327, 'missing_details'),
(5328, 'missing_details'),
(5329, 'missing_details'),
(5330, 'missing_details'),
(5331, 'missing_details'),
(5332, 'missing_details'),
(5333, 'missing_details'),
(5334, 'missing_details'),
(5335, 'missing_details'),
(5336, 'missing_details'),
(5337, 'missing_details'),
(5338, 'missing_details'),
(5339, 'missing_details'),
(5340, 'missing_details'),
(5341, 'missing_details'),
(5342, 'missing_details'),
(5343, 'missing_details'),
(5344, 'missing_details'),
(5345, 'missing_details'),
(5346, 'missing_details'),
(5347, 'missing_details'),
(5348, 'missing_details'),
(5349, 'missing_details'),
(5350, 'missing_details'),
(5351, 'missing_details'),
(5352, 'missing_details'),
(5353, 'missing_details'),
(5354, 'missing_details'),
(5355, 'missing_details'),
(5356, 'missing_details'),
(5357, 'missing_details'),
(5358, 'missing_details'),
(5359, 'missing_details'),
(5360, 'missing_details'),
(5361, 'missing_details'),
(5362, 'missing_details'),
(5363, 'missing_details'),
(5364, 'missing_details'),
(5365, 'missing_details'),
(5366, 'missing_details'),
(5367, 'missing_details'),
(5368, 'missing_details'),
(5369, 'missing_details'),
(5370, 'missing_details'),
(5371, 'missing_details'),
(5372, 'missing_details'),
(5373, 'missing_details'),
(5374, 'missing_details'),
(5375, 'missing_details'),
(5376, 'missing_details'),
(5377, 'missing_details'),
(5378, 'missing_details'),
(5379, 'missing_details'),
(5380, 'missing_details'),
(5381, 'missing_details'),
(5382, 'missing_details'),
(5383, 'missing_details'),
(5384, 'missing_details'),
(5385, 'missing_details'),
(5386, 'missing_details'),
(5387, 'missing_details'),
(5388, 'missing_details'),
(5389, 'missing_details'),
(5390, 'missing_details'),
(5391, 'missing_details'),
(5392, 'missing_details'),
(5393, 'missing_details'),
(5394, 'missing_details'),
(5395, 'missing_details'),
(5396, 'missing_details'),
(5397, 'missing_details'),
(5398, 'missing_details'),
(5399, 'missing_details'),
(5400, 'missing_details'),
(5401, 'missing_details'),
(5402, 'missing_details'),
(5403, 'missing_details'),
(5404, 'missing_details'),
(5405, 'missing_details'),
(5406, 'missing_details'),
(5407, 'missing_details'),
(5408, 'missing_details'),
(5409, 'missing_details'),
(5410, 'missing_details'),
(5411, 'missing_details'),
(5412, 'missing_details'),
(5413, 'missing_details'),
(5414, 'missing_details'),
(5415, 'missing_details'),
(5416, 'missing_details'),
(5417, 'missing_details'),
(5418, 'missing_details'),
(5519, 'missing_details'),
(5520, 'missing_details'),
(5521, 'missing_details'),
(5522, 'missing_details'),
(5523, 'missing_details'),
(5524, 'missing_details'),
(5525, 'missing_details'),
(5526, 'missing_details'),
(5527, 'missing_details'),
(5528, 'missing_details'),
(5529, 'missing_details'),
(5530, 'missing_details'),
(5531, 'missing_details'),
(5532, 'missing_details'),
(5533, 'missing_details'),
(5534, 'missing_details'),
(5535, 'missing_details'),
(5536, 'missing_details'),
(5537, 'missing_details'),
(5538, 'missing_details'),
(5539, 'missing_details'),
(5540, 'missing_details'),
(5541, 'missing_details'),
(5542, 'missing_details'),
(5543, 'missing_details'),
(5544, 'missing_details'),
(5545, 'missing_details'),
(5546, 'missing_details'),
(5547, 'missing_details'),
(5548, 'missing_details'),
(5549, 'missing_details'),
(5550, 'missing_details'),
(5551, 'missing_details'),
(5552, 'missing_details'),
(5553, 'missing_details'),
(5554, 'missing_details'),
(5555, 'missing_details'),
(5556, 'missing_details'),
(5557, 'missing_details'),
(5558, 'missing_details'),
(5559, 'missing_details'),
(5560, 'missing_details'),
(5561, 'missing_details'),
(5562, 'missing_details'),
(5563, 'missing_details'),
(5564, 'missing_details'),
(5565, 'missing_details'),
(5566, 'missing_details'),
(5567, 'missing_details'),
(5568, 'missing_details'),
(5569, 'missing_details'),
(5570, 'missing_details'),
(5571, 'missing_details'),
(5572, 'missing_details'),
(5573, 'missing_details'),
(5574, 'missing_details'),
(5575, 'missing_details'),
(5576, 'missing_details'),
(5577, 'missing_details'),
(5578, 'missing_details'),
(5579, 'missing_details'),
(5580, 'missing_details'),
(5581, 'missing_details'),
(5582, 'missing_details'),
(5583, 'missing_details'),
(5584, 'missing_details'),
(5585, 'missing_details'),
(5586, 'missing_details'),
(5587, 'missing_details'),
(5588, 'missing_details'),
(5589, 'missing_details'),
(5590, 'missing_details'),
(5591, 'missing_details'),
(5592, 'missing_details'),
(5593, 'missing_details'),
(5594, 'missing_details'),
(5595, 'missing_details'),
(5596, 'missing_details'),
(5597, 'missing_details'),
(5598, 'missing_details'),
(5599, 'missing_details'),
(5600, 'missing_details'),
(5601, 'missing_details'),
(5602, 'missing_details'),
(5603, 'missing_details'),
(5604, 'missing_details'),
(5605, 'missing_details'),
(5606, 'missing_details'),
(5607, 'missing_details'),
(5608, 'missing_details'),
(5609, 'missing_details'),
(5610, 'missing_details'),
(5611, 'missing_details'),
(5612, 'missing_details'),
(5613, 'missing_details'),
(5614, 'missing_details'),
(5615, 'missing_details'),
(5616, 'missing_details'),
(5617, 'missing_details'),
(5618, 'missing_details')
       ) v(firm_id, src)
  join public.v2_firms f on f.firm_id = v.firm_id
on conflict (firm_id) do nothing;

-- 4. Hand-outs skip closed firms (only the added "not closed" lines change).
CREATE OR REPLACE FUNCTION public.v2_next_firm(p_key_id uuid, p_job text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
declare
  bk public.v2_bot_keys;
  v_job text := coalesce(public.v2_work_current_job(), p_job);
  fn text := public.v2_work_job_fn(v_job);
  c public.v2_work_claims;
  r record;
  held boolean := true;
  n_held int;
  v_held jsonb;
  v_info jsonb;
  frm public.v2_firms;
  v_extra jsonb := '{}'::jsonb;
begin
  bk := public.v2_work_bot(p_key_id);
  if bk.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  if bk.frozen then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', format('Key frozen: %s, %s',
      coalesce(bk.freeze_reason, 'no reason'), to_char(bk.freeze_date at time zone 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  end if;
  if fn is null then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'unknown job');
  end if;
  if p_job is not null and p_job <> v_job then
    v_extra := jsonb_build_object('asked_job', p_job);
  end if;

  -- One call per key at a time, so parallel helpers of one bot never go past 10.
  perform pg_advisory_xact_lock(hashtext('v2_work_keys:' || v_job), bk.bot_key_id::int);

  -- A bot may hold up to 10 live claims for this job. At 10 it gets its oldest one back.
  select count(*) into n_held from public.v2_work_claims w
   where w.job = v_job and w.bot_key_id = bk.bot_key_id and w.done_at is null and w.expires_at > now();

  if n_held >= 10 then
    select * into c from public.v2_work_claims w
     where w.job = v_job and w.bot_key_id = bk.bot_key_id and w.done_at is null and w.expires_at > now()
     order by w.claimed_at, w.firm_id limit 1;
  else
    held := false;
    for r in execute format(
      'select g.firm_id from public.%I(null) g
         join public.v2_firms f on f.firm_id = g.firm_id and not coalesce(f.archived, false)
        where (case when $1 = ''deal_gaps'' then public.v2_work_hq_known(f.hq_country) else true end)
          and not public.v2_firm_research_held(g.firm_id)
          and not public.v2_firm_research_closed(g.firm_id)
          and not exists (select 1 from public.v2_work_claims w
                           where w.job = $1 and w.firm_id = g.firm_id
                             and (w.done_at is not null or w.expires_at > now()))
        order by g.sort_key desc, g.firm_id
        limit 50', fn) using v_job
    loop
      -- Skip a firm another bot is claiming right now (no waiting).
      continue when not pg_try_advisory_xact_lock(hashtext('v2_work_claims:' || v_job), r.firm_id::int);
      insert into public.v2_work_claims as w (job, firm_id, bot_key_id, claimed_at, expires_at, done_at)
      values (v_job, r.firm_id, bk.bot_key_id, now(), now() + interval '2 hours', null)
      on conflict (job, firm_id) do update
         set bot_key_id = excluded.bot_key_id, claimed_at = excluded.claimed_at, expires_at = excluded.expires_at
       where w.done_at is null and w.expires_at <= now()
      returning * into c;
      exit when found;
    end loop;

    -- deal_gaps only: reopen a done-but-still-gappy firm someone else finished.
    if c.firm_id is null and v_job = 'deal_gaps' then
      for r in execute format(
        'select g.firm_id from public.%I(null) g
           join public.v2_firms f on f.firm_id = g.firm_id and not coalesce(f.archived, false)
           join public.v2_work_claims w on w.job = $1 and w.firm_id = g.firm_id
          where public.v2_work_hq_known(f.hq_country)
            and not public.v2_firm_research_held(g.firm_id)
          and not public.v2_firm_research_closed(g.firm_id)
            and w.done_at is not null
            and w.bot_key_id is distinct from $2
          order by (g.sort_key - coalesce((g.info->>''dated_or_staged'')::bigint, 0)) desc, g.firm_id
          limit 50', fn) using v_job, bk.bot_key_id
      loop
        continue when not pg_try_advisory_xact_lock(hashtext('v2_work_claims:' || v_job), r.firm_id::int);
        update public.v2_work_claims as w
           set bot_key_id = bk.bot_key_id, claimed_at = now(), expires_at = now() + interval '2 hours', done_at = null
         where w.job = v_job and w.firm_id = r.firm_id
           and w.done_at is not null
           and w.bot_key_id is distinct from bk.bot_key_id
        returning * into c;
        exit when found;
      end loop;
    end if;
  end if;

  -- The key's live claims for this job after this call.
  select coalesce(jsonb_agg(w.firm_id order by w.claimed_at, w.firm_id), '[]'::jsonb) into v_held
    from public.v2_work_claims w
   where w.job = v_job and w.bot_key_id = bk.bot_key_id and w.done_at is null and w.expires_at > now();

  if c.firm_id is null then
    return jsonb_build_object('ok', true, 'bot_id', bk.bot_name, 'job', v_job, 'firm', null,
      'held_firm_ids', v_held, 'held_count', jsonb_array_length(v_held)) || v_extra;
  end if;

  execute format('select info from public.%I($1)', fn) into v_info using c.firm_id;
  select * into frm from public.v2_firms where firm_id = c.firm_id;
  return jsonb_build_object(
    'ok', true, 'bot_id', bk.bot_name, 'job', v_job, 'held', held,
    'claimed_at', c.claimed_at, 'expires_at', c.expires_at,
    'held_firm_ids', v_held, 'held_count', jsonb_array_length(v_held),
    'firm', jsonb_build_object('firm_id', frm.firm_id, 'name', frm.display_name, 'slug', frm.slug, 'website', frm.website_url)
            || coalesce(v_info, '{}'::jsonb)) || v_extra;
end
$function$;

CREATE OR REPLACE FUNCTION public.v2_section_claim(p_key_id uuid, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
declare
  v_ik bots.ingest_keys;
  v_bk public.v2_bot_keys;
  v_bot text;
  v_section text;
  v_fid bigint;
  v_got bigint;
  v_frm public.v2_firms;
  v_skip bigint[] := '{}';
  v_try int;
  v_hold_limit int := 10;
  v_held_ids bigint[] := '{}';
begin
  v_section := lower(btrim(coalesce(p_section, '')));
  if v_section not in ('legal', 'reviews', 'youtube') then
    return jsonb_build_object('ok', false, 'error', 'section must be legal, reviews, or youtube');
  end if;

  select * into v_ik from bots.ingest_keys where id = p_key_id and active;
  if not found or v_ik.bot_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  v_bot := v_ik.bot_id;
  -- Read the existing v2_bot_keys row. Do not rewrite it. Insert only when this bot has none yet.
  select * into v_bk from public.v2_bot_keys where bot_name = v_bot;
  if not found then
    insert into public.v2_bot_keys (bot_name, key_hash)
    values (v_bot, v_ik.key_hash)
    on conflict (bot_name) do nothing;
    select * into v_bk from public.v2_bot_keys where bot_name = v_bot;
  end if;
  if v_bk.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  if v_bk.frozen then
    return jsonb_build_object('ok', false, 'bot_id', v_bot, 'error', format('Key frozen: %s, %s', coalesce(v_bk.freeze_reason, 'no reason'), to_char(v_bk.freeze_date at time zone 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  end if;

  -- Lock this key's open holds in this section so two claims cannot pass the limit together.
  -- FOR UPDATE cannot be combined with array_agg, so the lock is a separate statement.
  perform 1
    from public.v2_section_holds h
   where h.section = v_section
     and h.bot_key_id = v_bk.bot_key_id
     and h.checked_at is null
     and h.claimed_at > now() - interval '6 hours'
   for update of h;
  select coalesce(array_agg(h.firm_id order by h.claimed_at, h.firm_id), '{}'::bigint[])
    into v_held_ids
    from public.v2_section_holds h
   where h.section = v_section
     and h.bot_key_id = v_bk.bot_key_id
     and h.checked_at is null
     and h.claimed_at > now() - interval '6 hours';
  if cardinality(v_held_ids) >= v_hold_limit then
    return jsonb_build_object(
      'ok', false,
      'bot_id', v_bot,
      'section', v_section,
      'error', format(
        'hold_limit: finish or mark done one of your %s firms first; held_firm_ids: %s',
        v_hold_limit,
        array_to_string(v_held_ids, ', ')),
      'held_firm_ids', to_jsonb(v_held_ids));
  end if;

  for v_try in 1..32 loop
    v_fid := null;
    select f.firm_id into v_fid
      from public.firm_summary s
      join public.v2_firms f on f.firm_id = s.firm_id
     where s.listed
       and s.firm_status = 'Active'
       and not coalesce(f.archived, false)
       and not (f.firm_id = any (v_skip))
       and not public.v2_firm_research_held(f.firm_id)
       and not public.v2_firm_research_closed(f.firm_id)
       and case v_section
             when 'legal' then not exists (
               select 1 from public.v2_legal_items li
                where li.firm_id = f.firm_id and li.is_current and not li.archived)
             when 'reviews' then not exists (
               select 1 from public.v2_reviews r
                where r.firm_id = f.firm_id and r.is_current and not r.archived)
             else not exists (
               select 1 from public.v2_interviews iv
                where iv.firm_id = f.firm_id and iv.is_current and not iv.archived)
           end
       and not exists (
             select 1 from public.v2_section_holds h
              where h.firm_id = f.firm_id
                and h.section = v_section
                and (h.checked_at is not null or h.claimed_at > now() - interval '6 hours'))
     order by s.deals desc, s.firm_id
     limit 1
     for update of f skip locked;
    if v_fid is null then
      return jsonb_build_object('ok', true, 'bot_id', v_bot, 'section', v_section, 'none_left', true);
    end if;

    v_got := null;
    insert into public.v2_section_holds (firm_id, section, bot_key_id, claimed_at)
    values (v_fid, v_section, v_bk.bot_key_id, now())
    on conflict (firm_id, section) do update
      set bot_key_id = excluded.bot_key_id,
          claimed_at = excluded.claimed_at
      where v2_section_holds.checked_at is null
        and v2_section_holds.claimed_at <= now() - interval '6 hours'
    returning firm_id into v_got;
    if found then
      exit;
    end if;
    v_skip := v_skip || v_fid;
  end loop;

  if v_got is null then
    return jsonb_build_object('ok', true, 'bot_id', v_bot, 'section', v_section, 'none_left', true);
  end if;
  select * into v_frm from public.v2_firms where firm_id = v_got;
  return jsonb_build_object(
    'ok', true, 'bot_id', v_bot, 'section', v_section,
    'firm_id', v_frm.firm_id, 'slug', v_frm.slug, 'name', v_frm.display_name, 'website', v_frm.website_url);
end
$function$;

CREATE OR REPLACE FUNCTION public.v2_research_claim(p_key_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  ik bots.ingest_keys;
  bk public.v2_bot_keys;
  bot text;
  fid bigint;
  frm public.v2_firms;
BEGIN
  SELECT * INTO ik FROM bots.ingest_keys WHERE id = p_key_id AND active;
  IF NOT FOUND OR ik.bot_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  END IF;
  bot := ik.bot_id;
  SELECT * INTO bk FROM public.v2_bot_keys WHERE bot_name = bot;
  IF NOT FOUND OR bk.key_hash IS DISTINCT FROM ik.key_hash THEN
  INSERT INTO public.v2_bot_keys (bot_name, key_hash) VALUES (bot, ik.key_hash)
    ON CONFLICT (bot_name) DO UPDATE SET key_hash = EXCLUDED.key_hash RETURNING * INTO bk;
  END IF;
  IF bk.frozen THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', format('Key frozen: %s, %s', coalesce(bk.freeze_reason, 'no reason'), to_char(bk.freeze_date AT TIME ZONE 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  END IF;

  fid := null;
  WITH picked AS (
    SELECT q.firm_id
      FROM public.v2_research_assignments q
      JOIN public.v2_firms f ON f.firm_id = q.firm_id
     WHERE q.done_at IS NULL
       AND NOT coalesce(f.archived, false)
       AND NOT public.v2_firm_research_held(q.firm_id)
       AND NOT public.v2_firm_research_closed(q.firm_id)
       AND (
         q.claimed_by IS NULL
         OR coalesce(q.expires_at, q.claimed_at + interval '6 hours') <= now()
       )
     ORDER BY CASE q.priority WHEN 'top' THEN 0 ELSE 1 END, q.firm_id
     FOR UPDATE OF q SKIP LOCKED
     LIMIT 1
  )
  UPDATE public.v2_research_assignments a
     SET claimed_by = bot,
         claimed_at = now(),
         expires_at = now() + interval '6 hours'
    FROM picked
   WHERE a.firm_id = picked.firm_id
  RETURNING a.firm_id INTO fid;

  IF fid IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'bot_id', bot, 'none_left', true);
  END IF;

  SELECT * INTO frm FROM public.v2_firms WHERE firm_id = fid;
  RETURN jsonb_build_object(
    'ok', true,
    'bot_id', bot,
    'firm_id', frm.firm_id,
    'slug', frm.slug,
    'name', frm.display_name,
    'website', frm.website_url);
END
$function$;
