#if defined _shavit_pc_included
 #endinput
#endif
#define _shavit_pc_included

/**
 * Retrieves the percentage of the map completed by the target player.
 * 
 * @param target                    target index.
 *
 * @return                          Returns the percentage of the map completed or -1.0 if data is unavailable.
 */
native float Shavit_GetTargetPC(int target);

public SharedPlugin __pl_shavit_pc =
{
    name = "shavit-pc",
    file = "shavit-pc.smx",
#if defined REQUIRE_PLUGIN
    required = 1
#else
    required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_pc_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_GetTargetPC");
}
#endif